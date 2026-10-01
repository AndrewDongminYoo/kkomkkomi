// The domain imports only Dart core libraries, so `@immutable` from
// `package:meta` is not available here. Every field of the class is final.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:kkomkkomi/domain/name.dart';

/// The cleaning company that uses the app. The report header prints [name].
final class CompanyProfile {
  new({required String name}) : name = normalizeName(name);

  final String name;

  @override
  bool operator ==(Object other) => other is CompanyProfile && other.name == name;

  @override
  int get hashCode => name.hashCode;
}
