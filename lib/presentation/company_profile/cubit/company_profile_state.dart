// Every field of the class is final, and `package:meta`, which has `@immutable`, is not a dependency.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

part of 'company_profile_cubit.dart';

enum CompanyProfileStatus {
  /// The profile is on its way from storage.
  loading,

  /// Storage did not give the profile.
  loadFailed,

  /// [CompanyProfileState.name] holds what storage has.
  ready,
}

final class CompanyProfileState {
  const new({this.status = CompanyProfileStatus.loading, this.name = '', this.entry = NameEntry.editing});

  final CompanyProfileStatus status;

  /// The saved company name, or an empty text when no profile was saved.
  final String name;

  /// What became of the company name that the form last submitted.
  final NameEntry entry;

  CompanyProfileState copyWith({CompanyProfileStatus? status, String? name, NameEntry? entry}) =>
      CompanyProfileState(status: status ?? this.status, name: name ?? this.name, entry: entry ?? this.entry);

  @override
  bool operator ==(Object other) =>
      other is CompanyProfileState && other.status == status && other.name == name && other.entry == entry;

  @override
  int get hashCode => Object.hash(status, name, entry);
}
