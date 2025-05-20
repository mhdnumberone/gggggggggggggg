// lib/core/error_handling/result.dart

/// نموذج النتيجة الموحد للتعامل مع العمليات التي قد تنجح أو تفشل
class Result<T> {
  final T? _value;
  final String? _error;
  final bool _isSuccess;

  /// إنشاء نتيجة ناجحة
  const Result.success(T value)
      : _value = value,
        _error = null,
        _isSuccess = true;

  /// إنشاء نتيجة فاشلة
  const Result.failure(String error)
      : _value = null,
        _error = error,
        _isSuccess = false;

  /// التحقق مما إذا كانت النتيجة ناجحة
  bool get isSuccess => _isSuccess;

  /// التحقق مما إذا كانت النتيجة فاشلة
  bool get isFailure => !_isSuccess;

  /// الحصول على القيمة في حالة النجاح
  T get value {
    if (_isSuccess) {
      return _value as T;
    }
    throw Exception('محاولة الوصول إلى قيمة نتيجة فاشلة: $_error');
  }

  /// الحصول على رسالة الخطأ في حالة الفشل
  String get error {
    if (!_isSuccess) {
      return _error!;
    }
    throw Exception('محاولة الوصول إلى خطأ نتيجة ناجحة');
  }

  /// تنفيذ دالة مختلفة حسب حالة النتيجة
  R fold<R>(R Function(T value) onSuccess, R Function(String error) onFailure) {
    if (_isSuccess) {
      return onSuccess(_value as T);
    } else {
      return onFailure(_error!);
    }
  }

  /// تحويل النتيجة إلى نتيجة من نوع آخر
  Result<R> map<R>(R Function(T value) transform) {
    if (_isSuccess) {
      try {
        return Result.success(transform(_value as T));
      } catch (e) {
        return Result.failure('فشل في تحويل النتيجة: $e');
      }
    } else {
      return Result.failure(_error!);
    }
  }

  /// تحويل النتيجة إلى نتيجة من نوع آخر مع إمكانية الفشل
  Result<R> flatMap<R>(Result<R> Function(T value) transform) {
    if (_isSuccess) {
      try {
        return transform(_value as T);
      } catch (e) {
        return Result.failure('فشل في تحويل النتيجة: $e');
      }
    } else {
      return Result.failure(_error!);
    }
  }

  @override
  String toString() {
    if (_isSuccess) {
      return 'Success: $_value';
    } else {
      return 'Failure: $_error';
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Result<T> &&
        other._isSuccess == _isSuccess &&
        other._value == _value &&
        other._error == _error;
  }

  @override
  int get hashCode => Object.hash(_isSuccess, _value, _error);
}
