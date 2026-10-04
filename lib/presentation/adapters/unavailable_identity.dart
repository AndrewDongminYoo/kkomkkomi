import 'package:kkomkkomi/application/application.dart';

/// Reports that identity is unavailable, for a flavor that does not start Firebase.
final class UnavailableIdentity implements Identity {
  const new();

  @override
  Future<String?> currentUserId() async => null;

  /// The flavor never signs in, so the device holds no account.
  @override
  Future<void> deleteAccount() async {}

  /// The flavor holds no account, so no token holds a paid entitlement.
  @override
  Future<bool> hasPaidEntitlement() async => false;
}
