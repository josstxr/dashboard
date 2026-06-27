import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

Future<String?> healthyTNotificationLogoPath() async {
  try {
    final logoBytes = await rootBundle.load('assets/logo.png');
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/healthy_t_notification_logo.png');
    final bytes = logoBytes.buffer.asUint8List();

    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }

    return file.path;
  } catch (_) {
    return null;
  }
}
