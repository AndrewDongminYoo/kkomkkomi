import 'package:kkomkkomi/app/app.dart';
import 'package:kkomkkomi/bootstrap.dart';

Future<void> main() async {
  await bootstrap(() => const App());
}
