// 🌎 Project imports:
import 'package:kkomkkomi/app/app.dart';
import 'package:kkomkkomi/bootstrap.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

Future<void> main() async {
  await bootstrap(
    (repositories, identity, entitlements, publishQueue, recovery) => App(
      repositories: repositories,
      identity: identity,
      entitlements: entitlements,
      publishQueue: publishQueue,
      recovery: recovery,
    ),
    identity: const UnavailableIdentity(),
    entitlements: const FreeEntitlements(),
    publisher: const UnavailablePublisher(),
  );
}
