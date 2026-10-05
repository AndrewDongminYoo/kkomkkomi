/// Opens a web page outside the app, such as the terms of use, so that tests never open one.
abstract interface class ExternalLinks {
  /// Opens [uri] in the app that the device uses for it, and answers whether it opened. The call does not throw.
  Future<bool> open(Uri uri);
}
