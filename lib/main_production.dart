import 'package:kkomkkomi/app/app.dart';
import 'package:kkomkkomi/bootstrap.dart';
import 'package:kkomkkomi/firebase/firebase.dart';

Future<void> main() async {
  await bootstrap(
    (repositories, identity) => App(repositories: repositories, identity: identity),
    identity: FirebaseIdentity(),
  );
}
