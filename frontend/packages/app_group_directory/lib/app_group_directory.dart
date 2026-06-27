import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class AppGroupDirectory {
  static const _channel =
      MethodChannel('me.wolszon.app_group_directory/channel');

  static Future<Directory?> getAppGroupDirectory(String groupId) async {
    final path =
        await _channel.invokeMethod<String>('getAppGroupDirectory', groupId);

    if (path == null) {
      return null;
    }

    return Directory(path);
  }
}
