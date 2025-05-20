// lib/core/history/history_item.dart

enum OperationType {
  encryptAes,
  decryptAes,
  encodeZeroWidth,
  decodeZeroWidth,
  encryptThenHide,
  revealThenDecrypt,
  encryptFile,
  decryptFile,
  embedImageStego,
  extractImageStego,
}

class HistoryItem {
  final String id;
  final DateTime timestamp;
  final OperationType operationType;
  final String? originalInput; // النص الأصلي قبل التشفير/الإخفاء
  final String? processedInput; // النص المشفر/المخفي المدخل للعملية العكسية
  final String? coverText; // نص الغطاء المستخدم
  final String output; // الناتج النهائي للعملية
  final bool usedPassword;
  final bool usedSteganography;

  HistoryItem({
    required this.id,
    required this.timestamp,
    required this.operationType,
    this.originalInput,
    this.processedInput,
    this.coverText,
    required this.output,
    required this.usedPassword,
    required this.usedSteganography,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'operationType': operationType.index,
        if (originalInput != null) 'originalInput': originalInput,
        if (processedInput != null) 'processedInput': processedInput,
        if (coverText != null) 'coverText': coverText,
        'output': output,
        'usedPassword': usedPassword,
        'usedSteganography': usedSteganography,
      };

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: DateTime.parse(json['timestamp']),
      operationType: OperationType
          .values[json['operationType'] ?? OperationType.encryptAes.index],
      originalInput: json['originalInput'] as String?,
      processedInput: json['processedInput'] as String?,
      coverText: json['coverText'] as String?,
      output: json['output'] ?? '',
      usedPassword: json['usedPassword'] ?? false,
      usedSteganography: json['usedSteganography'] ?? false,
    );
  }

  String get operationDescription {
    switch (operationType) {
      case OperationType.encryptAes:
        return 'تشفير نص (AES-GCM)';
      case OperationType.decryptAes:
        return 'فك تشفير نص (AES-GCM)';
      case OperationType.encodeZeroWidth:
        return 'إخفاء نص (Zero-Width)';
      case OperationType.decodeZeroWidth:
        return 'كشف نص (Zero-Width)';
      case OperationType.encryptThenHide:
        return 'تشفير نص ثم إخفاء';
      case OperationType.revealThenDecrypt:
        return 'كشف نص ثم فك تشفير';
      case OperationType.encryptFile:
        return 'تشفير ملف';
      case OperationType.decryptFile:
        return 'فك تشفير ملف';
      case OperationType.embedImageStego:
        return 'إخفاء بيانات في صورة';
      case OperationType.extractImageStego:
        return 'استخراج بيانات من صورة';
    }
  }
}
