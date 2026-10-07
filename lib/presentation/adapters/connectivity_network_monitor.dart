// 📦 Package imports:
import 'package:connectivity_plus/connectivity_plus.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';

/// Tells when the device gets a network again, from the network state that `connectivity_plus` reports.
final class ConnectivityNetworkMonitor implements NetworkMonitor {
  /// The `connectivity` argument replaces the plugin in a test.
  const new({this._connectivity});

  final Connectivity? _connectivity;

  @override
  Stream<void> get restored {
    // The plugin can report the state that the device is in when the stream starts. That state is no return of the
    // network, so only a change from no network to a network counts.
    var offline = false;
    return (_connectivity ?? Connectivity()).onConnectivityChanged.where((results) {
      final online = results.any((result) => result != ConnectivityResult.none);
      final returned = online && offline;
      offline = !online;
      return returned;
    });
  }
}
