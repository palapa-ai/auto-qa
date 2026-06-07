// Driver-enabled entrypoint for the example app.
//
// In your own project, copy this file into `test_driver/` and change the import
// to your package's `main.dart`. `enableFlutterDriverExtension()` turns on the
// Flutter Driver extension so auto-qa can connect over the Dart VM Service and
// drive the running app. This entrypoint is for testing only — it lives outside
// `lib/`, so the driver extension never reaches a production build.
import 'package:auto_qa_example/main.dart' as app;
import 'package:flutter_driver/driver_extension.dart';

void main() {
  enableFlutterDriverExtension();
  app.main();
}
