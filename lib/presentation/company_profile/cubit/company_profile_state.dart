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

/// Where the deletion of all data is.
enum DataDeletion {
  /// No deletion runs.
  idle,

  /// A deletion is on its way.
  deleting,

  /// Everything is deleted, and the app is as at its first launch.
  deleted,
}

final class CompanyProfileState {
  const new({
    this.status = CompanyProfileStatus.loading,
    this.name = '',
    this.phone = '',
    this.entry = NameEntry.editing,
    this.deletion = DataDeletion.idle,
    this.deletionFailure,
  });

  final CompanyProfileStatus status;

  /// The saved company name, or an empty text when no profile was saved.
  final String name;
  final String phone;

  /// What became of the company name that the form last submitted.
  final NameEntry entry;

  final DataDeletion deletion;

  /// The step at which the last deletion stopped, or null when none stopped.
  final DeletionStep? deletionFailure;

  CompanyProfileState copyWith({CompanyProfileStatus? status, String? name, String? phone, NameEntry? entry}) =>
      CompanyProfileState(
        status: status ?? this.status,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        entry: entry ?? this.entry,
        deletion: deletion,
        deletionFailure: deletionFailure,
      );

  /// This state with [deletion], and [failure] as the step at which the deletion stopped.
  CompanyProfileState withDeletion(DataDeletion deletion, {DeletionStep? failure}) => CompanyProfileState(
    status: status,
    name: name,
    phone: phone,
    entry: entry,
    deletion: deletion,
    deletionFailure: failure,
  );

  @override
  bool operator ==(Object other) =>
      other is CompanyProfileState &&
      other.status == status &&
      other.name == name &&
      other.phone == phone &&
      other.entry == entry &&
      other.deletion == deletion &&
      other.deletionFailure == deletionFailure;

  @override
  int get hashCode => Object.hash(status, name, phone, entry, deletion, deletionFailure);
}
