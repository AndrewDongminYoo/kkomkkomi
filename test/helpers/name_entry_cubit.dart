import 'package:bloc/bloc.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

/// A cubit whose state is a name entry, for a test that drives a name dialog.
class NameEntryCubit extends Cubit<NameEntry> {
  new() : super(NameEntry.editing);

  void become(NameEntry entry) => emit(entry);
}
