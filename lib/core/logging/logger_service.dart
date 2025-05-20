// lib/core/logging/logger_service.dart
import 'package:flutter/foundation.dart'; // For kDebugMode

enum LogLevel { debug, info, warn, error }

// lib/core/logging/logger_service.dart
// ... (الكود السابق لـ LoggerService) ...
class LoggerService {
  final String _className;
  LogLevel currentLogLevel = kDebugMode ? LogLevel.debug : LogLevel.info;

  LoggerService(this._className);

  bool get isDebugEnabled => currentLogLevel.index <= LogLevel.debug.index;
  // ... (باقي getters) ...

  void _log(LogLevel level, String tag, String message,
      [dynamic error, StackTrace? stackTrace]) {
    if (level.index >= currentLogLevel.index) {
      final timestamp = DateTime.now().toIso8601String();
      String logMessage =
          '$timestamp [${level.toString().split('.').last.toUpperCase()}] [$_className] $tag: $message';
      if (error != null) {
        logMessage += '\nError: $error';
      }
      // فقط اطبع stackTrace لـ errors أو إذا تم تمريره بشكل صريح لـ warn
      if (stackTrace != null &&
          (level == LogLevel.error || level == LogLevel.warn)) {
        logMessage += '\nStackTrace: $stackTrace';
      }
      // استبدال print
      // print(logMessage); // هذا هو السطر الذي يسبب info - Don't invoke 'print' ...
      debugPrint(
          logMessage); // استخدام debugPrint الذي لا يظهر في release builds بنفس الطريقة
    }
  }

  void debug(String tag, String message) {
    _log(LogLevel.debug, tag, message);
  }

  void info(String tag, String message) {
    _log(LogLevel.info, tag, message);
  }

  // تعديل warn ليقبل error و stackTrace كمعاملات اختيارية مسماة أو موضعية
  void warn(String tag, String message,
      {dynamic error, StackTrace? stackTrace}) {
    // استخدام معاملات مسماة
    _log(LogLevel.warn, tag, message, error, stackTrace);
  }
  // أو إذا كنت تفضل موضعية:
  // void warn(String tag, String message, [dynamic error, StackTrace? stackTrace]) {
  //   _log(LogLevel.warn, tag, message, error, stackTrace);
  // }

  void error(String tag, String message,
      [dynamic error, StackTrace? stackTrace]) {
    _log(LogLevel.error, tag, message, error, stackTrace);
  }
}
