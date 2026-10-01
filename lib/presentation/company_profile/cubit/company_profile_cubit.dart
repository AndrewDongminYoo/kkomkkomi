import 'package:bloc/bloc.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/shared/name_entry.dart';

part 'company_profile_state.dart';

/// Loads the company profile and saves the company name.
class CompanyProfileCubit extends Cubit<CompanyProfileState> {
  new({required this._companyProfile}) : super(const CompanyProfileState());

  final CompanyProfileRepository _companyProfile;

  /// Reads the saved profile from storage.
  Future<void> load() async {
    if (state.status != CompanyProfileStatus.loading) emit(const CompanyProfileState());
    try {
      final profile = await _companyProfile.load();
      if (isClosed) return;
      emit(CompanyProfileState(status: CompanyProfileStatus.ready, name: profile?.name ?? ''));
    } on Exception catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(const CompanyProfileState(status: CompanyProfileStatus.loadFailed));
    }
  }

  /// Saves [name] as the company name.
  ///
  /// [CompanyProfileState.entry] tells what became of [name]. A call while a name is on its way to storage does
  /// nothing.
  Future<void> save(String name) async {
    if (state.entry == NameEntry.saving) return;
    final CompanyProfile profile;
    try {
      profile = CompanyProfile(name: name);
    } on DomainException catch (exception) {
      emit(state.copyWith(entry: NameEntry.refusedBy(exception)));
      return;
    }
    emit(state.copyWith(entry: NameEntry.saving));
    try {
      await _companyProfile.save(profile);
      if (isClosed) return;
      emit(state.copyWith(name: profile.name, entry: NameEntry.saved));
    } on Exception catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(entry: NameEntry.failed));
    }
  }
}
