import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:kkomkkomi/application/application.dart';

part 'client_link_state.dart';

/// Shows the link of one client, closes it, and replaces it with a new link, through the publish queue of the app.
///
/// A close is done on the phone when storage takes it, and on the backend only when its revoke job is done. So the
/// state reads the revoke jobs of the client again at each change of a job, and says that a link is closed only after
/// its job is done. A job that fails for a reason that a retry can fix stays pending, and the link stays closing.
class ClientLinkCubit extends Cubit<ClientLinkState> {
  new({required this._clientId, required this._publishQueue}) : super(const ClientLinkState());

  final String _clientId;
  final PublishQueue _publishQueue;

  StreamSubscription<PublishJob>? _updates;

  /// How many reads of the link started, so that a read that a later read overtook does not show older data.
  var _reads = 0;

  /// Reads whether the flavor publishes, and the link of the client, and then follows each change of a job.
  Future<void> load() async {
    if (!_publishQueue.isAvailable) {
      _show(const ClientLinkState(status: ClientLinkStatus.unavailable));
      return;
    }
    if (state.status != ClientLinkStatus.loading) emit(const ClientLinkState());
    // A publish can give the client its first link, and a revoke job can close one, while the screen is open.
    _updates ??= _publishQueue.updates.listen((_) => unawaited(_refresh()));
    try {
      await _read(status: ClientLinkStatus.ready);
    } on Exception catch (error, stackTrace) {
      _report(error, stackTrace);
      _show(const ClientLinkState(status: ClientLinkStatus.loadFailed));
    }
  }

  /// Closes the open link of the client: every link of the client that was sent stops opening when the revoke job is
  /// done, and the next link share makes a new link. A call does nothing while the client has no open link and while
  /// the state takes no action.
  Future<void> closeLink() => _request(() => _publishQueue.revokeClientPage(_clientId), keepsOpenLink: false);

  /// Replaces the open link of the client with a new link: the old links stop opening when the revoke job is done,
  /// and the queue publishes the reports again under the new link. A call does nothing while the client has no open
  /// link and while the state takes no action.
  Future<void> makeNewLink() => _request(() => _publishQueue.reissueClientPage(_clientId), keepsOpenLink: true);

  Future<void> _request(Future<Object?> Function() request, {required bool keepsOpenLink}) async {
    if (!state.takesAction || !state.hasOpenLink) return;
    _show(state.copyWith(status: ClientLinkStatus.requesting));
    final Object? result;
    try {
      result = await request();
    } on Exception catch (error, stackTrace) {
      _report(error, stackTrace);
      _show(state.copyWith(status: ClientLinkStatus.requestFailed));
      return;
    }
    try {
      await _read(status: ClientLinkStatus.ready);
    } on Exception catch (error, stackTrace) {
      _report(error, stackTrace);
      if (result == null) {
        // The request found no open link to close, so storage took no revoke job from it, and no job update will
        // correct a closing state.
        _show(state.copyWith(status: ClientLinkStatus.ready, hasOpenLink: false));
      } else {
        // Storage took the revoke and its job, which has not run yet, so the link is closing.
        _show(state.copyWith(status: ClientLinkStatus.ready, hasOpenLink: keepsOpenLink, isClosing: true));
      }
    }
  }

  Future<void> _refresh() async {
    try {
      await _read();
    } on Exception catch (error, stackTrace) {
      // The state keeps what it showed, and the next change of a job reads again.
      _report(error, stackTrace);
    }
  }

  /// Reads the link of the client and shows it with [status], or with the status that the state has when the read
  /// ends. A read that a later read overtook shows only [status], because its data can be older.
  Future<void> _read({ClientLinkStatus? status}) async {
    final read = ++_reads;
    final hasOpenLink = await _publishQueue.hasOpenPage(_clientId);
    final revokes = await _publishQueue.revokeJobsOf(_clientId);
    if (read != _reads) {
      if (status != null) _show(state.copyWith(status: status));
      return;
    }
    bool any(PublishJobStatus jobStatus) => revokes.any((job) => job.status == jobStatus);
    // The deletion of all data stops a pending revoke job before it deletes the page, so such a job does not say that
    // the link still opens: the deletion either deleted the page or failed at that delete.
    bool stopped({required bool byDeletion}) => revokes.any(
      (job) => job.status == PublishJobStatus.failed && (job.failure == PublishFailure.deletion) == byDeletion,
    );
    _show(
      ClientLinkState(
        status: status ?? state.status,
        hasOpenLink: hasOpenLink,
        isClosing: any(PublishJobStatus.pending),
        hasFailedClose: stopped(byDeletion: false),
        hasUnfinishedDeletion: stopped(byDeletion: true),
        hasClosedLink: any(PublishJobStatus.done),
      ),
    );
  }

  void _show(ClientLinkState next) {
    if (!isClosed) emit(next);
  }

  void _report(Object error, StackTrace stackTrace) {
    if (!isClosed) addError(error, stackTrace);
  }

  @override
  Future<void> close() async {
    await _updates?.cancel();
    _updates = null;
    await super.close();
  }
}
