import 'package:kkomkkomi/application/application.dart';

/// Reports that identity is unavailable, for a flavor that does not start Firebase.
final class UnavailableIdentity implements Identity {
  const new();

  @override
  Future<String?> currentUserId() async => null;
}
