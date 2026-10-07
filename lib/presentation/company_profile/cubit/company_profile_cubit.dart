// 📦 Package imports:
import 'package:bloc/bloc.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/shared/name_entry.dart';

part 'company_profile_state.dart';

/// Loads the company profile, saves the company name, and deletes all data.
class CompanyProfileCubit extends Cubit<CompanyProfileState> {
  new({required this._companyProfile, required this._deleteAllData}) : super(const CompanyProfileState());

  final CompanyProfileRepository _companyProfile;
  final DeleteAllData _deleteAllData;

  /// Deletes everything that the app holds for the person, and the app then is as at its first launch.
  ///
  /// [CompanyProfileState.deletion] tells where the deletion is, and [CompanyProfileState.deletionFailure] names the
  /// step at which it stopped. A call while a deletion or a name is on its way, or after the deletion completed, does
  /// nothing.
  Future<void> deleteAllData() async {
    if (state.deletion != DataDeletion.idle || state.entry == NameEntry.saving) return;
    emit(state.withDeletion(DataDeletion.deleting));
    try {
      await _deleteAllData();
      if (isClosed) return;
      emit(state.withDeletion(DataDeletion.deleted));
    } on DeletionFailure catch (failure, stackTrace) {
      if (isClosed) return;
      addError(failure, stackTrace);
      emit(state.withDeletion(DataDeletion.idle, failure: failure.step));
    }
  }

  /// Reads the saved profile from storage.
  Future<void> load() async {
    if (state.status != CompanyProfileStatus.loading) emit(const CompanyProfileState());
    try {
      final profile = await _companyProfile.load();
      if (isClosed) return;
      emit(
        CompanyProfileState(status: CompanyProfileStatus.ready, name: profile?.name ?? '', phone: profile?.phone ?? ''),
      );
    } on Exception catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(const CompanyProfileState(status: CompanyProfileStatus.loadFailed));
    }
  }

  /// Saves [name] as the company name.
  ///
  /// [CompanyProfileState.entry] tells what became of [name]. A call while a name is on its way to storage, while a
  /// deletion of all data is on its way, or after it completed does nothing, so that no name is stored again after the
  /// erase.
  Future<void> save(String name, {String phone = ''}) async {
    if (state.entry == NameEntry.saving || state.deletion != DataDeletion.idle) return;
    final CompanyProfile profile;
    try {
      profile = CompanyProfile(name: name, phone: phone);
    } on DomainException catch (exception) {
      emit(state.copyWith(entry: NameEntry.refusedBy(exception)));
      return;
    }
    emit(state.copyWith(entry: NameEntry.saving));
    try {
      await _companyProfile.save(profile);
      if (isClosed) return;
      emit(state.copyWith(name: profile.name, phone: profile.phone, entry: NameEntry.saved));
    } on Exception catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(entry: NameEntry.failed));
    }
  }
}
