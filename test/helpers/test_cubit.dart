import 'package:bloc/bloc.dart';

/// A cubit that a test drives to see what a `BlocObserver` receives.
class TestCubit extends Cubit<int> {
  new() : super(0);

  void change() => emit(state + 1);

  void fail() => addError(StateError('failed'), StackTrace.current);
}
