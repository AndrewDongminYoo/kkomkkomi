/// Tells when the device gets a network again, so that tests never read the network state of the device.
abstract interface class NetworkMonitor {
  /// An event each time the device goes from no network to a network.
  ///
  /// A network is no proof that the backend can be reached, so the queue only uses an event to run its jobs at once,
  /// and its retry delay still covers a backend that cannot be reached.
  Stream<void> get restored;
}
