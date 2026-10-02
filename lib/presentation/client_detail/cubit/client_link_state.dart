// Every field of the class is final, and `package:meta`, which has `@immutable`, is not a dependency.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

part of 'client_link_cubit.dart';

enum ClientLinkStatus {
  /// The cubit reads whether the flavor publishes and what became of the links of the client.
  loading,

  /// The flavor has no backend, so the screen shows nothing about links.
  unavailable,

  /// Storage did not give the link of the client.
  loadFailed,

  /// The state holds what storage has, and an action can start.
  ready,

  /// A close or a new link is on its way to storage.
  requesting,

  /// Storage did not take the last close or new link, and the state holds what it held before.
  requestFailed,
}

final class ClientLinkState {
  const new({
    this.status = ClientLinkStatus.loading,
    this.hasOpenLink = false,
    this.isClosing = false,
    this.hasFailedClose = false,
    this.hasUnfinishedDeletion = false,
    this.hasClosedLink = false,
  });

  final ClientLinkStatus status;

  /// Whether the client has an open link, which anyone who has it can open.
  final bool hasOpenLink;

  /// Whether a link of the client is closed on the phone and not yet on the backend, so that it can still open.
  final bool isClosing;

  /// Whether the close of a link of the client stopped for a reason of the backend or the flavor before it reached the
  /// backend, so that the link still opens.
  final bool hasFailedClose;

  /// Whether the deletion of all data stopped the close of a link of the client and then did not finish, so that the
  /// link may still open. The deletion deletes the page after it stops the close, so the page is gone when the
  /// deletion failed at a later step, and not when it failed at that delete.
  final bool hasUnfinishedDeletion;

  /// Whether a link of the client is closed on the backend.
  final bool hasClosedLink;

  /// Whether a close or a new link can start in this status.
  bool get takesAction => status == ClientLinkStatus.ready || status == ClientLinkStatus.requestFailed;

  ClientLinkState copyWith({
    ClientLinkStatus? status,
    bool? hasOpenLink,
    bool? isClosing,
  }) => ClientLinkState(
    status: status ?? this.status,
    hasOpenLink: hasOpenLink ?? this.hasOpenLink,
    isClosing: isClosing ?? this.isClosing,
    hasFailedClose: hasFailedClose,
    hasUnfinishedDeletion: hasUnfinishedDeletion,
    hasClosedLink: hasClosedLink,
  );

  @override
  bool operator ==(Object other) =>
      other is ClientLinkState &&
      other.status == status &&
      other.hasOpenLink == hasOpenLink &&
      other.isClosing == isClosing &&
      other.hasFailedClose == hasFailedClose &&
      other.hasUnfinishedDeletion == hasUnfinishedDeletion &&
      other.hasClosedLink == hasClosedLink;

  @override
  int get hashCode => Object.hash(status, hasOpenLink, isClosing, hasFailedClose, hasUnfinishedDeletion, hasClosedLink);

  @override
  String toString() =>
      'ClientLinkState(${status.name}, open: $hasOpenLink, closing: $isClosing, failed: $hasFailedClose, '
      'deletion unfinished: $hasUnfinishedDeletion, closed: $hasClosedLink)';
}
