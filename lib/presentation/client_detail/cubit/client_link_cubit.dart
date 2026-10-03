import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:kkomkkomi/application/application.dart';

part 'client_link_state.dart';

/// Shows the link of one client, closes it, and replaces it with a new link, through the publish queue of the app.
///
/// A close is done on the phone when storage takes it, and on the backend only when its revoke job is done. So the
/// state reads pages and revoke jobs at committed changes. A link is closed after a completed revoke or confirmed
/// page deletion. Unconfirmed deletion intent quarantines its page but does not prove that access is removed.
/// A job that fails for a reason that a retry can fix stays pending, and the link stays closing.
class ClientLinkCubit extends Cubit<ClientLinkState> {
  new({required this._clientId, required this._publishQueue}) : super(const ClientLinkState());

  final String _clientId;
  final PublishQueue _publishQueue;

  StreamSubscription<PublishJob>? _updates;
  StreamSubscription<String>? _pageChanges;

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
    _pageChanges ??= _publishQueue.pageChanges.listen((clientId) {
      if (clientId == _clientId) unawaited(_refresh());
    });
    await _read(status: ClientLinkStatus.ready);
  }

  /// Closes the open link of the client: every link of the client that was sent stops opening when the revoke job is
  /// done, and the next link share makes a new link. A call does nothing while the client has no open link and while
  /// the state takes no action.
  Future<void> closeLink() => _request(() => _publishQueue.revokeClientPage(_clientId));

  /// Replaces the open link of the client with a new link: the old links stop opening when the revoke job is done,
  /// and the queue publishes the reports again under the new link. A call does nothing while the client has no open
  /// link and while the state takes no action.
  Future<void> makeNewLink() => _request(() => _publishQueue.reissueClientPage(_clientId));

  Future<void> _request(Future<Object?> Function() request) async {
    if (!state.takesAction || !state.hasOpenLink) return;
    _show(state.copyWith(status: ClientLinkStatus.requesting));
    try {
      await request();
    } on Exception catch (error, stackTrace) {
      _report(error, stackTrace);
      _show(state.copyWith(status: ClientLinkStatus.requestFailed));
      return;
    }
    await _read(status: ClientLinkStatus.ready);
  }

  Future<void> _refresh() => _read();

  /// Every current read owns its success and failure. Superseded reads change nothing.
  Future<void> _read({ClientLinkStatus? status}) async {
    final read = ++_reads;
    try {
      final pages = await _publishQueue.pagesOf(_clientId);
      final revokes = await _publishQueue.revokeJobsOf(_clientId);
      if (read != _reads) return;
      final confirmed = {
        for (final page in pages)
          if (page.serverDeletedAt != null) page.id,
      };
      final unconfirmed = revokes.where((job) => !confirmed.contains(job.pageId));
      bool stopped({required bool byDeletion}) => unconfirmed.any(
        (job) => job.status == PublishJobStatus.failed && (job.failure == PublishFailure.deletion) == byDeletion,
      );
      _show(
        ClientLinkState(
          status: status ?? ClientLinkStatus.ready,
          hasOpenLink: pages.any((page) => page.isOpen),
          isClosing: unconfirmed.any((job) => job.status == PublishJobStatus.pending),
          hasFailedClose: stopped(byDeletion: false),
          hasUnfinishedDeletion: pages.any((page) => page.isServerDeletionPending) || stopped(byDeletion: true),
          hasClosedLink: confirmed.isNotEmpty || revokes.any((job) => job.status == PublishJobStatus.done),
        ),
      );
    } on Object catch (error, stackTrace) {
      if (read != _reads) return;
      _report(error, stackTrace);
      _show(const ClientLinkState(status: ClientLinkStatus.loadFailed));
    }
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
    await _pageChanges?.cancel();
    _updates = null;
    _pageChanges = null;
    await super.close();
  }
}
