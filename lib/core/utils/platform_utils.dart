import 'dart:io';

/// Utility to check the current platform.
class PlatformUtils {
  static bool get isWindows => Platform.isWindows;
  static bool get isAndroid => Platform.isAndroid;
  static bool get isMobile => Platform.isAndroid || Platform.isIOS;
}
