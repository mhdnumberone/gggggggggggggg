// lib/core/logging/logger_service.dart
import "package:logger/logger.dart";

class LoggerService {
  final String className;
  late final Logger _logger;

  LoggerService(this.className) {
    _logger = Logger(
      printer: PrettyPrinter(
        methodCount: 1,
        errorMethodCount: 5,
        lineLength: 100,
        colors: true,
        printEmojis: true,
        printTime: true,
      ),
      // You can set the minimum log level here, e.g., Level.warning for production
      // level: Level.debug, 
    );
  }

  // Info log
  void i(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i("$className: $message", error: error, stackTrace: stackTrace);
  }

  // Debug log
  void d(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.d("$className: $message", error: error, stackTrace: stackTrace);
  }

  // Warning log
  void w(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w("$className: $message", error: error, stackTrace: stackTrace);
  }

  // Error log
  void e(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e("$className: $message", error: error, stackTrace: stackTrace);
  }

  // Verbose log
  void v(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.v("$className: $message", error: error, stackTrace: stackTrace);
  }

  // WTF (What a Terrible Failure) log
  void wtf(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.f("$className: $message", error: error, stackTrace: stackTrace);
  }
}

