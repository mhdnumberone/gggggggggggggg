// lib/core/encryption/encryption_service.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cryptography/cryptography.dart' as cryptography;

import '../error_handling/error_handler.dart';
import '../error_handling/result.dart';
import '../logging/logger_provider.dart';
import '../logging/logger_service.dart';

/// خدمة التشفير الموحدة للتطبيق
/// توفر واجهة موحدة لجميع عمليات التشفير وفك التشفير
class EncryptionService {
  final LoggerService _logger;
  final ErrorHandler _errorHandler;
  
  // طول مفتاح AES بالبت
  static const int _aesKeyLength = 256;
  
  // طول IV بالبايت
  static const int _ivLength = 16;
  
  // عدد دورات اشتقاق المفتاح
  static const int _pbkdf2Iterations = 10000;

  EncryptionService(this._logger, this._errorHandler);

  /// تشفير نص باستخدام AES-GCM
  Future<Result<String>> encryptAesGcm(String plainText, String password) async {
    try {
      return await _errorHandler.retryWithBackoff(
        operation: () async {
          // اشتقاق المفتاح من كلمة المرور
          final keyData = await _deriveKey(password, _aesKeyLength ~/ 8);
          
          // إنشاء IV عشوائي
          final iv = _generateRandomBytes(_ivLength);
          
          // إنشاء مفتاح AES
          final key = encrypt.Key(keyData);
          final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
          
          // تشفير النص
          final encrypted = encrypter.encrypt(
            plainText,
            iv: encrypt.IV(iv),
          );
          
          // دمج IV مع النص المشفر
          final result = base64.encode(iv + encrypted.bytes);
          
          _logger.debug('EncryptionService:encryptAesGcm', 'تم تشفير النص بنجاح');
          return Result.success(result);
        },
        context: 'EncryptionService:encryptAesGcm',
      );
    } catch (e, stackTrace) {
      final appError = _errorHandler.handleError(
        e,
        stackTrace,
        context: 'EncryptionService:encryptAesGcm',
      );
      return Result.failure(appError.message);
    }
  }

  /// فك تشفير نص مشفر باستخدام AES-GCM
  Future<Result<String>> decryptAesGcm(String encryptedText, String password) async {
    try {
      return await _errorHandler.retryWithBackoff(
        operation: () async {
          // فك ترميز النص المشفر من Base64
          final encryptedBytes = base64.decode(encryptedText);
          
          // التحقق من أن النص المشفر يحتوي على IV على الأقل
          if (encryptedBytes.length <= _ivLength) {
            return Result.failure('النص المشفر غير صالح');
          }
          
          // استخراج IV والنص المشفر
          final iv = encryptedBytes.sublist(0, _ivLength);
          final cipherBytes = encryptedBytes.sublist(_ivLength);
          
          // اشتقاق المفتاح من كلمة المرور
          final keyData = await _deriveKey(password, _aesKeyLength ~/ 8);
          
          // إنشاء مفتاح AES
          final key = encrypt.Key(keyData);
          final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
          
          // فك تشفير النص
          final decrypted = encrypter.decrypt64(
            base64.encode(cipherBytes),
            iv: encrypt.IV(iv),
          );
          
          _logger.debug('EncryptionService:decryptAesGcm', 'تم فك تشفير النص بنجاح');
          return Result.success(decrypted);
        },
        context: 'EncryptionService:decryptAesGcm',
      );
    } catch (e, stackTrace) {
      final appError = _errorHandler.handleError(
        e,
        stackTrace,
        context: 'EncryptionService:decryptAesGcm',
      );
      return Result.failure(appError.message);
    }
  }

  /// تشفير ملف باستخدام AES-GCM
  Future<Result<Uint8List>> encryptFileAesGcm(Uint8List fileData, String password) async {
    try {
      return await _errorHandler.retryWithBackoff(
        operation: () async {
          // اشتقاق المفتاح من كلمة المرور
          final keyData = await _deriveKey(password, _aesKeyLength ~/ 8);
          
          // إنشاء IV عشوائي
          final iv = _generateRandomBytes(_ivLength);
          
          // إنشاء مفتاح AES
          final key = encrypt.Key(keyData);
          final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
          
          // تشفير البيانات
          final encrypted = encrypter.encryptBytes(
            fileData,
            iv: encrypt.IV(iv),
          );
          
          // دمج IV مع البيانات المشفرة
          final result = Uint8List.fromList(iv + encrypted.bytes);
          
          _logger.debug('EncryptionService:encryptFileAesGcm', 'تم تشفير الملف بنجاح');
          return Result.success(result);
        },
        context: 'EncryptionService:encryptFileAesGcm',
      );
    } catch (e, stackTrace) {
      final appError = _errorHandler.handleError(
        e,
        stackTrace,
        context: 'EncryptionService:encryptFileAesGcm',
      );
      return Result.failure(appError.message);
    }
  }

  /// فك تشفير ملف مشفر باستخدام AES-GCM
  Future<Result<Uint8List>> decryptFileAesGcm(Uint8List encryptedData, String password) async {
    try {
      return await _errorHandler.retryWithBackoff(
        operation: () async {
          // التحقق من أن البيانات المشفرة تحتوي على IV على الأقل
          if (encryptedData.length <= _ivLength) {
            return Result.failure('البيانات المشفرة غير صالحة');
          }
          
          // استخراج IV والبيانات المشفرة
          final iv = encryptedData.sublist(0, _ivLength);
          final cipherBytes = encryptedData.sublist(_ivLength);
          
          // اشتقاق المفتاح من كلمة المرور
          final keyData = await _deriveKey(password, _aesKeyLength ~/ 8);
          
          // إنشاء مفتاح AES
          final key = encrypt.Key(keyData);
          final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
          
          // فك تشفير البيانات
          final decrypted = encrypter.decryptBytes(
            encrypt.Encrypted(cipherBytes),
            iv: encrypt.IV(iv),
          );
          
          _logger.debug('EncryptionService:decryptFileAesGcm', 'تم فك تشفير الملف بنجاح');
          return Result.success(Uint8List.fromList(decrypted));
        },
        context: 'EncryptionService:decryptFileAesGcm',
      );
    } catch (e, stackTrace) {
      final appError = _errorHandler.handleError(
        e,
        stackTrace,
        context: 'EncryptionService:decryptFileAesGcm',
      );
      return Result.failure(appError.message);
    }
  }

  /// تشفير نص باستخدام تشفير متماثل بسيط (للبيانات غير الحساسة)
  Result<String> encryptSimple(String plainText, String key) {
    try {
      // اشتقاق مفتاح بسيط من المفتاح المقدم
      final keyBytes = utf8.encode(key);
      final keyHash = sha256.convert(keyBytes).bytes;
      
      // تحويل النص إلى بايتات
      final textBytes = utf8.encode(plainText);
      
      // تشفير البيانات باستخدام XOR
      final encrypted = List<int>.filled(textBytes.length, 0);
      for (int i = 0; i < textBytes.length; i++) {
        encrypted[i] = textBytes[i] ^ keyHash[i % keyHash.length];
      }
      
      // تحويل البيانات المشفرة إلى Base64
      final result = base64.encode(encrypted);
      
      _logger.debug('EncryptionService:encryptSimple', 'تم تشفير النص بنجاح');
      return Result.success(result);
    } catch (e, stackTrace) {
      final appError = _errorHandler.handleError(
        e,
        stackTrace,
        context: 'EncryptionService:encryptSimple',
      );
      return Result.failure(appError.message);
    }
  }

  /// فك تشفير نص مشفر باستخدام تشفير متماثل بسيط
  Result<String> decryptSimple(String encryptedText, String key) {
    try {
      // اشتقاق مفتاح بسيط من المفتاح المقدم
      final keyBytes = utf8.encode(key);
      final keyHash = sha256.convert(keyBytes).bytes;
      
      // فك ترميز النص المشفر من Base64
      final encryptedBytes = base64.decode(encryptedText);
      
      // فك تشفير البيانات باستخدام XOR
      final decrypted = List<int>.filled(encryptedBytes.length, 0);
      for (int i = 0; i < encryptedBytes.length; i++) {
        decrypted[i] = encryptedBytes[i] ^ keyHash[i % keyHash.length];
      }
      
      // تحويل البيانات المفكوكة إلى نص
      final result = utf8.decode(decrypted);
      
      _logger.debug('EncryptionService:decryptSimple', 'تم فك تشفير النص بنجاح');
      return Result.success(result);
    } catch (e, stackTrace) {
      final appError = _errorHandler.handleError(
        e,
        stackTrace,
        context: 'EncryptionService:decryptSimple',
      );
      return Result.failure(appError.message);
    }
  }

  /// حساب تجزئة (hash) لنص باستخدام SHA-256
  Result<String> hashSha256(String input) {
    try {
      final bytes = utf8.encode(input);
      final digest = sha256.convert(bytes);
      return Result.success(digest.toString());
    } catch (e, stackTrace) {
      final appError = _errorHandler.handleError(
        e,
        stackTrace,
        context: 'EncryptionService:hashSha256',
      );
      return Result.failure(appError.message);
    }
  }

  /// اشتقاق مفتاح من كلمة مرور باستخدام PBKDF2
  Future<Uint8List> _deriveKey(String password, int keyLength) async {
    final algorithm = cryptography.Pbkdf2(
      macAlgorithm: cryptography.Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: keyLength * 8,
    );
    
    // إنشاء salt عشوائي
    final salt = _generateRandomBytes(16);
    
    // اشتقاق المفتاح
    final secretKey = await algorithm.deriveKey(
      secretKey: cryptography.SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    
    // استخراج البيانات
    final keyData = await secretKey.extractBytes();
    return Uint8List.fromList(keyData);
  }

  /// إنشاء بايتات عشوائية
  Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}

/// مزود لخدمة التشفير
final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  final logger = ref.watch(appLoggerProvider);
  final errorHandler = ref.watch(errorHandlerProvider);
  return EncryptionService(logger, errorHandler);
});
