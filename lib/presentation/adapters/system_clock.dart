import 'package:kkomkkomi/application/application.dart';

/// Tells the time of the device.
final class SystemClock implements Clock {
  const new();

  @override
  DateTime now() => DateTime.now();
}
