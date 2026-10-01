import 'dart:math';

import 'package:kkomkkomi/application/application.dart';

/// Makes identifiers of 128 random bits, written as 32 hexadecimal digits.
final class RandomIdGenerator implements IdGenerator {
  /// The `random` argument is the source of the bits, and the default is the secure source of the platform.
  const new({this._random});

  final Random? _random;

  @override
  String newId() {
    final random = _random ?? Random.secure();
    return [for (var byte = 0; byte < 16; byte++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
  }
}
