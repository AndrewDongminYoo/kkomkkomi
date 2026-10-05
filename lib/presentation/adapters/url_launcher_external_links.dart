import 'dart:developer';

import 'package:kkomkkomi/application/application.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a link in the browser or the store app of the device through `url_launcher`.
final class UrlLauncherExternalLinks implements ExternalLinks {
  /// The `launch` argument replaces `launchUrl` of `url_launcher` in a test.
  const new({this._launch = _launchExternally});

  final Future<bool> Function(Uri uri) _launch;

  /// Opens [uri] outside the app. The adapter does not ask `canLaunchUrl` first: the `url_launcher` README says that
  /// it can answer false when `launchUrl` would work, for example on Android 11 and later without a `<queries>` entry.
  static Future<bool> _launchExternally(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  Future<bool> open(Uri uri) async {
    try {
      return await _launch(uri);
    } on Object catch (error, stackTrace) {
      // `launchUrl` answers false or throws a `PlatformException`, and a platform without the plugin throws an
      // `Error`. The port does not throw, so the clause catches every object.
      log('The link did not open: $error', stackTrace: stackTrace);
      return false;
    }
  }
}
