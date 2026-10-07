// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/presentation/shared/save_guard.dart';

import '../../helpers/helpers.dart';

void main() {
  group('SaveGuard', () {
    /// Opens a guarded screen over a host screen and returns the count of taps that the guarded screen took.
    Future<List<int>> openGuarded(WidgetTester tester, {required bool isSaving}) async {
      final taps = <int>[];
      await tester.pumpApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SaveGuard(
                  isSaving: isSaving,
                  child: Scaffold(
                    appBar: AppBar(),
                    body: TextButton(onPressed: () => taps.add(taps.length), child: const Text('guarded')),
                  ),
                ),
              ),
            ),
            child: const Text('host'),
          ),
        ),
      );
      await tester.tap(find.text('host'));
      await tester.pumpAndSettle();
      return taps;
    }

    testWidgets('takes no touch and no back press while a change is on its way to storage', (tester) async {
      final taps = await openGuarded(tester, isSaving: true);

      await tester.tap(find.text('guarded'), warnIfMissed: false);
      await tester.tap(find.byType(BackButton), warnIfMissed: false);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(taps, isEmpty);
      expect(find.text('guarded'), findsOneWidget);
    });

    testWidgets('takes touches and closes on a back press while no change is on its way', (tester) async {
      final taps = await openGuarded(tester, isSaving: false);

      await tester.tap(find.text('guarded'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(taps, [0]);
      expect(find.text('guarded'), findsNothing);
      expect(find.text('host'), findsOneWidget);
    });
  });
}
