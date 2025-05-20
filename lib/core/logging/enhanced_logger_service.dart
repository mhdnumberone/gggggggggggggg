// lib/core/logging/enhanced_logger_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

/// مستويات السجل المختلفة
enum LogLevel {
  debug,
  info,
  warn,
  error,
}

/// خدمة التسجيل المحسنة مع دعم تدوير السجلات وتشفير البيانات الحساسة
class EnhancedLoggerService {
  // الحد الأقصى لحجم ملف السجل بالبايت (5 ميجابايت)
  static const int _maxLogFileSize = 5 * 1024 * 1024;
  
  // الحد الأقصى لعدد ملفات السجل القديمة للاحتفاظ بها
  static const int _maxLogFileHistory = 3;
  
  // مسار ملف السجل الحالي
  String? _currentLogFilePath;
  
  // مؤقت لتنظيف السجلات القديمة
  Timer? _cleanupTimer;
  
  // قائمة الكلمات المحظورة التي يجب تشفيرها في السجلات
  final List<String> _sensitiveWords = [
    'password',
    'token',
    'key',
    'secret',
    'credential',
    'auth',
    'كلمة المرور',
    'رمز',
    'مفتاح',
    'سر',
  ];

  EnhancedLoggerService() {
    _initializeLogger();
  }

  /// تهيئة خدمة التسجيل
  Future<void> _initializeLogger() async {
    try {
      // إنشاء مجلد السجلات إذا لم يكن موجودًا
      final appDocDir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${appDocDir.path}/logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      
      // تعيين مسار ملف السجل الحالي
      _currentLogFilePath = '${logDir.path}/app_log_${DateTime.now().millisecondsSinceEpoch}.log';
      
      // كتابة سطر بداية في ملف السجل
      final startupMessage = _formatLogEntry(
        LogLevel.info,
        'LoggerService',
        'تم بدء تشغيل خدمة التسجيل',
      );
      await _writeToLogFile(startupMessage);
      
      // بدء مؤقت لتنظيف السجلات القديمة (كل 24 ساعة)
      _cleanupTimer = Timer.periodic(const Duration(hours: 24), (_) {
        _cleanupOldLogs();
      });
      
      // تنظيف السجلات القديمة عند بدء التشغيل
      _cleanupOldLogs();
    } catch (e) {
      debugPrint('فشل في تهيئة خدمة التسجيل: $e');
    }
  }

  /// تسجيل رسالة تصحيح
  Future<void> debug(String tag, String message) async {
    await _log(LogLevel.debug, tag, message);
  }

  /// تسجيل رسالة معلومات
  Future<void> info(String tag, String message) async {
    await _log(LogLevel.info, tag, message);
  }

  /// تسجيل رسالة تحذير
  Future<void> warn(String tag, String message) async {
    await _log(LogLevel.warn, tag, message);
  }

  /// تسجيل رسالة خطأ
  Future<void> error(String tag, String message, [dynamic error, StackTrace? stackTrace]) async {
    final errorMessage = error != null ? '$message\nError: $error' : message;
    final fullMessage = stackTrace != null ? '$errorMessage\n$stackTrace' : errorMessage;
    await _log(LogLevel.error, tag, fullMessage);
  }

  /// تسجيل رسالة بمستوى محدد
  Future<void> _log(LogLevel level, String tag, String message) async {
    try {
      // تشفير البيانات الحساسة
      final sanitizedMessage = _sanitizeMessage(message);
      
      // تنسيق رسالة السجل
      final logEntry = _formatLogEntry(level, tag, sanitizedMessage);
      
      // طباعة الرسالة في وضع التصحيح
      if (kDebugMode) {
        debugPrint(logEntry);
      }
      
      // كتابة الرسالة في ملف السجل
      await _writeToLogFile(logEntry);
      
      // التحقق من حجم ملف السجل وتدويره إذا لزم الأمر
      await _checkAndRotateLogFile();
    } catch (e) {
      debugPrint('فشل في تسجيل الرسالة: $e');
    }
  }

  /// تنسيق رسالة السجل
  String _formatLogEntry(LogLevel level, String tag, String message) {
    final timestamp = DateTime.now().toIso8601String();
    final levelStr = level.toString().split('.').last.toUpperCase();
    return '[$timestamp] $levelStr/$tag: $message';
  }

  /// كتابة رسالة في ملف السجل
  Future<void> _writeToLogFile(String logEntry) async {
    if (_currentLogFilePath == null) return;
    
    try {
      final file = File(_currentLogFilePath!);
      await file.writeAsString('$logEntry\n', mode: FileMode.append);
    } catch (e) {
      debugPrint('فشل في كتابة السجل: $e');
    }
  }

  /// التحقق من حجم ملف السجل وتدويره إذا لزم الأمر
  Future<void> _checkAndRotateLogFile() async {
    if (_currentLogFilePath == null) return;
    
    try {
      final file = File(_currentLogFilePath!);
      if (await file.exists()) {
        final fileSize = await file.length();
        if (fileSize > _maxLogFileSize) {
          await _rotateLogFile();
        }
      }
    } catch (e) {
      debugPrint('فشل في التحقق من حجم ملف السجل: $e');
    }
  }

  /// تدوير ملف السجل
  Future<void> _rotateLogFile() async {
    if (_currentLogFilePath == null) return;
    
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${appDocDir.path}/logs');
      
      // إنشاء ملف سجل جديد
      final newLogFilePath = '${logDir.path}/app_log_${DateTime.now().millisecondsSinceEpoch}.log';
      
      // تسجيل رسالة تدوير السجل
      final rotationMessage = _formatLogEntry(
        LogLevel.info,
        'LoggerService',
        'تم تدوير ملف السجل من $_currentLogFilePath إلى $newLogFilePath',
      );
      await _writeToLogFile(rotationMessage);
      
      // تحديث مسار ملف السجل الحالي
      _currentLogFilePath = newLogFilePath;
      
      // كتابة سطر بداية في ملف السجل الجديد
      final startupMessage = _formatLogEntry(
        LogLevel.info,
        'LoggerService',
        'تم إنشاء ملف سجل جديد',
      );
      await _writeToLogFile(startupMessage);
    } catch (e) {
      debugPrint('فشل في تدوير ملف السجل: $e');
    }
  }

  /// تنظيف السجلات القديمة
  Future<void> _cleanupOldLogs() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${appDocDir.path}/logs');
      
      if (await logDir.exists()) {
        final logFiles = await logDir
            .list()
            .where((entity) => entity is File && entity.path.endsWith('.log'))
            .toList();
        
        // ترتيب الملفات حسب تاريخ التعديل (الأقدم أولاً)
        logFiles.sort((a, b) {
          return a.statSync().modified.compareTo(b.statSync().modified);
        });
        
        // حذف الملفات القديمة إذا كان عددها يتجاوز الحد الأقصى
        if (logFiles.length > _maxLogFileHistory + 1) { // +1 للملف الحالي
          final filesToDelete = logFiles.sublist(0, logFiles.length - _maxLogFileHistory - 1);
          for (final file in filesToDelete) {
            if (file.path != _currentLogFilePath) {
              await file.delete();
              debug('LoggerService', 'تم حذف ملف السجل القديم: ${file.path}');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('فشل في تنظيف السجلات القديمة: $e');
    }
  }

  /// تشفير البيانات الحساسة في الرسالة
  String _sanitizeMessage(String message) {
    String sanitized = message;
    
    // تشفير الكلمات المحظورة
    for (final word in _sensitiveWords) {
      final regex = RegExp(r'(' + word + r'[=:]\s*)[^\s,;]+', caseSensitive: false);
      sanitized = sanitized.replaceAllMapped(regex, (match) {
        final prefix = match.group(1) ?? '';
        final sensitive = match.group(0)?.substring(prefix.length) ?? '';
        final hashed = _hashSensitiveData(sensitive);
        return '$prefix[REDACTED:$hashed]';
      });
    }
    
    return sanitized;
  }

  /// تشفير بيانات حساسة باستخدام SHA-256
  String _hashSensitiveData(String data) {
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 8); // استخدام جزء فقط من التجزئة
  }

  /// التخلص من الموارد
  void dispose() {
    _cleanupTimer?.cancel();
  }
}

/// مزود لخدمة التسجيل المحسنة
final enhancedLoggerServiceProvider = Provider<EnhancedLoggerService>((ref) {
  final logger = EnhancedLoggerService();
  ref.onDispose(() {
    logger.dispose();
  });
  return logger;
});
