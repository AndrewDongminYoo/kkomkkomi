// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

class _MockConnectivity extends Mock implements Connectivity;

void main() {
  group('ConnectivityNetworkMonitor', () {
    late StreamController<List<ConnectivityResult>> changes;
    late NetworkMonitor monitor;

    setUp(() {
      changes = StreamController<List<ConnectivityResult>>();
      final connectivity = _MockConnectivity();
      when(() => connectivity.onConnectivityChanged).thenAnswer((_) => changes.stream);
      monitor = ConnectivityNetworkMonitor(connectivity: connectivity);
    });

    test('reports each change from no network to a network, and no other state', () async {
      final restored = <void>[];
      final subscription = monitor.restored.listen(restored.add);
      addTearDown(subscription.cancel);

      // The state at the start is no return of the network.
      changes.add([ConnectivityResult.wifi]);
      await pumpEventQueue();
      expect(restored, isEmpty);

      changes.add([ConnectivityResult.none]);
      changes.add([ConnectivityResult.none]);
      await pumpEventQueue();
      expect(restored, isEmpty);

      changes.add([ConnectivityResult.mobile, ConnectivityResult.vpn]);
      await pumpEventQueue();
      expect(restored, hasLength(1));

      changes.add([ConnectivityResult.wifi]);
      changes.add([ConnectivityResult.none]);
      changes.add([ConnectivityResult.wifi]);
      await pumpEventQueue();
      expect(restored, hasLength(2));
    });
  });
}
