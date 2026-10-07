// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/app/app.dart';
import 'package:kkomkkomi/billing/billing.dart';
import 'package:kkomkkomi/bootstrap.dart';
import 'package:kkomkkomi/firebase/firebase.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

Future<void> main() async {
  // One identity, because the RevenueCat app user ID is the Firebase user ID.
  final identity = FirebaseIdentity();
  await bootstrap(
    (repositories, identity, entitlements, publishQueue, recovery) => App(
      repositories: repositories,
      identity: identity,
      entitlements: entitlements,
      publishQueue: publishQueue,
      recovery: recovery,
    ),
    identity: identity,
    // An empty key and a platform without RevenueCat give a build without subscriptions, on purpose.
    entitlements:
        revenueCatEntitlementsFor(identity: identity, platform: defaultTargetPlatform) ?? const FreeEntitlements(),
    publisher: FirebasePublisher(),
  );
}
