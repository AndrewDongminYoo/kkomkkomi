// 🌎 Project imports:
import 'package:kkomkkomi/application/report_share.dart';

/// Hands a report link to the share sheet of the device, so that tests never open one.
abstract interface class LinkShare {
  /// Opens the share sheet with [link].
  ///
  /// The call does not tell whether the person sent the link. Throws a [ReportShareException] when the share sheet
  /// did not open.
  Future<void> shareLink(Uri link);
}
