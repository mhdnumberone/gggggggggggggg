// lib/core/error_handling/error_handler.dart
import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/logger_provider.dart';
import '../logging/logger_service.dart';

/// نوع الخطأ لتحديد كيفية معالجته
enum ErrorType {
  /// أخطاء الشبكة
  network,

  /// أخطاء المصادقة
  authentication,

  /// أخطاء قاعدة البيانات
  database,

  /// أخطاء التشفير
  encryption,

  /// أخطاء الملفات
  file,

  /// أخطاء عامة
  general,
}

/// نموذج موحد للأخطاء
class AppError {
  final String message;
  final ErrorType type;
  final dynamic originalError;
  final StackTrace? stackTrace;
  final String? code;

  AppError({
    required this.message,
    required this.type,
    this.originalError,
    this.stackTrace,
    this.code,
  });

  /// إنشاء خطأ من استثناء
  factory AppError.fromException(dynamic error, StackTrace stackTrace) {
    if (error is SocketException || error is TimeoutException) {
      return AppError(
        message:
            'حدث خطأ في الاتصال بالشبكة. يرجى التحقق من اتصالك بالإنترنت والمحاولة مرة أخرى.',
        type: ErrorType.network,
        originalError: error,
        stackTrace: stackTrace,
      );
    } else if (error is FirebaseAuthException) {
      return AppError(
        message: _getAuthErrorMessage(error.code),
        type: ErrorType.authentication,
        originalError: error,
        stackTrace: stackTrace,
        code: error.code,
      );
    } else if (error is FirebaseException) {
      return AppError(
        message: _getFirebaseErrorMessage(error.code),
        type: ErrorType.database,
        originalError: error,
        stackTrace: stackTrace,
        code: error.code,
      );
    } else {
      return AppError(
        message: 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.',
        type: ErrorType.general,
        originalError: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// الحصول على رسالة خطأ المصادقة
  static String _getAuthErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'لم يتم العثور على مستخدم بهذا البريد الإلكتروني.';
      case 'wrong-password':
        return 'كلمة المرور غير صحيحة.';
      case 'invalid-email':
        return 'البريد الإلكتروني غير صالح.';
      case 'user-disabled':
        return 'تم تعطيل هذا الحساب.';
      case 'email-already-in-use':
        return 'البريد الإلكتروني مستخدم بالفعل.';
      case 'operation-not-allowed':
        return 'هذه العملية غير مسموح بها.';
      case 'weak-password':
        return 'كلمة المرور ضعيفة جدًا.';
      default:
        return 'حدث خطأ في المصادقة. يرجى المحاولة مرة أخرى.';
    }
  }

  /// الحصول على رسالة خطأ Firebase
  static String _getFirebaseErrorMessage(String code) {
    switch (code) {
      case 'permission-denied':
        return 'ليس لديك صلاحية للوصول إلى هذه البيانات.';
      case 'unavailable':
        return 'الخدمة غير متوفرة حاليًا. يرجى المحاولة مرة أخرى لاحقًا.';
      case 'not-found':
        return 'لم يتم العثور على البيانات المطلوبة.';
      case 'already-exists':
        return 'البيانات موجودة بالفعل.';
      default:
        return 'حدث خطأ في قاعدة البيانات. يرجى المحاولة مرة أخرى.';
    }
  }

  /// تشفير محتوى الخطأ لمنع تسرب المعلومات الحساسة
  String getSecureErrorMessage() {
    // تشفير الرسائل التي قد تحتوي على معلومات حساسة
    switch (type) {
      case ErrorType.authentication:
      case ErrorType.encryption:
        return 'حدث خطأ في العملية. يرجى المحاولة مرة أخرى.';
      default:
        return message;
    }
  }
}

/// معالج الأخطاء الموحد
class ErrorHandler {
  final LoggerService _logger;

  ErrorHandler(this._logger);

  /// معالجة الخطأ وإرجاع نموذج خطأ موحد
  AppError handleError(
    dynamic error,
    StackTrace stackTrace, {
    String? context,
  }) {
    final appError = AppError.fromException(error, stackTrace);

    // تسجيل الخطأ
    _logger.error(
      context ?? 'ErrorHandler',
      appError.message,
      appError.originalError,
      appError.stackTrace ?? stackTrace,
    );

    return appError;
  }

  /// عرض رسالة خطأ للمستخدم
  void showErrorToUser(BuildContext context, AppError error) {
    // استخدام رسالة آمنة لمنع تسرب المعلومات الحساسة
    final secureMessage = error.getSecureErrorMessage();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(secureMessage),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  /// استراتيجية إعادة المحاولة مع الانسحاب التدريجي
  Future<T> retryWithBackoff<T>({
    required Future<T> Function() operation,
    required String context,
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
  }) async {
    int retryCount = 0;
    Duration delay = initialDelay;

    while (true) {
      try {
        return await operation();
      } catch (e, stackTrace) {
        retryCount++;

        if (retryCount >= maxRetries) {
          _logger.error(
            context,
            'فشلت المحاولة بعد $maxRetries محاولات',
            e,
            stackTrace,
          );
          rethrow;
        }

        _logger.warn(
          context,
          'فشلت المحاولة $retryCount من $maxRetries. إعادة المحاولة بعد ${delay.inMilliseconds}ms',
        );

        await Future.delayed(delay);

        // زيادة التأخير بشكل تدريجي (تأخير تراجعي أسي)
        delay *= 2;
      }
    }
  }
}

/// مزود لمعالج الأخطاء
final errorHandlerProvider = Provider<ErrorHandler>((ref) {
  final logger = ref.watch(appLoggerProvider);
  return ErrorHandler(logger);
});
