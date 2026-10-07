// 📦 Package imports:
import 'package:share_plus/share_plus.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';

/// Opens the share sheet of the device with a report link through `share_plus`.
final class SharePlusLinkShare implements LinkShare {
  const new();

  @override
  Future<void> shareLink(Uri link) async {
    try {
      // The answer says whether the person picked an app or closed the sheet. Neither is a failure of the share.
      await SharePlus.instance.share(ShareParams(uri: link));
    } on Exception catch (error, stackTrace) {
      Error.throwWithStackTrace(ReportShareException(cause: error), stackTrace);
    }
  }
}
