import 'package:material_ui/material_ui.dart';

abstract interface class StillCameraDriver {
  Future<void> initialize();
  Widget preview();
  Future<String> takePicture();
  Future<void> dispose();
}
