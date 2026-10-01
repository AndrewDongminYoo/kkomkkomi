import 'package:kkomkkomi/domain/domain_exception.dart';

/// Trims [raw], and throws an [EmptyNameException] when nothing is left.
String normalizeName(String raw) {
  final name = raw.trim();
  if (name.isEmpty) throw const EmptyNameException();
  return name;
}
