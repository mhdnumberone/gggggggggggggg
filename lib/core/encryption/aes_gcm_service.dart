// lib/core/encryption/aes_gcm_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// لا حاجة لاستيراد LoggerService هنا إذا لم يتم استخدامه داخليًا

final aesGcmServiceProvider = Provider((ref) => AesGcmService());

class AesGcmService {
  final AesGcm _aesGcm = AesGcm.with256bits();
  final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 100000,
    bits: 256,
  );

  Future<String> encryptWithPassword(String plainText, String password) async {
    try {
      final salt = SecretKeyData.random(length: 16).bytes;
      final secretKey = await _pbkdf2.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );
      final iv = SecretKeyData.random(length: 12).bytes;
      final plainBytes = utf8.encode(plainText);
      final secretBox = await _aesGcm.encrypt(
        plainBytes,
        secretKey: secretKey,
        nonce: iv,
      );
      final combined = Uint8List.fromList(
          salt + iv + secretBox.cipherText + secretBox.mac.bytes);
      return base64UrlEncode(combined);
    } catch (e) {
      // Logged by the calling Notifier
      throw Exception('Encryption failed: ${e.toString()}');
    }
  }

  Future<String> decryptWithPassword(
      String base64CipherText, String password) async {
    try {
      final combined = base64Url.decode(base64CipherText);
      if (combined.length < (16 + 12 + 0 + 16)) {
        throw Exception('Invalid encrypted data format: too short.');
      }
      final salt = combined.sublist(0, 16);
      final iv = combined.sublist(16, 16 + 12);
      final cipherText = combined.sublist(16 + 12, combined.length - 16);
      final macBytes = combined.sublist(combined.length - 16);
      final mac = Mac(macBytes);
      final secretKey = await _pbkdf2.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );
      final secretBox = SecretBox(cipherText, nonce: iv, mac: mac);
      final decryptedBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
      );
      return utf8.decode(decryptedBytes);
    } on SecretBoxAuthenticationError {
      // Logged by the calling Notifier
      throw Exception('Decryption failed: Wrong password or data corrupted.');
    } catch (e) {
      // Logged by the calling Notifier
      if (e is Exception && e.toString().contains('Authentication failed')) {
        throw Exception('Decryption failed: Wrong password or data corrupted.');
      }
      throw Exception('Decryption failed: ${e.toString()}');
    }
  }

  Future<Uint8List> encryptBytesWithPassword(
      Uint8List plainBytes, String password) async {
    try {
      final salt = SecretKeyData.random(length: 16).bytes;
      final secretKey = await _pbkdf2.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );
      final iv = SecretKeyData.random(length: 12).bytes;
      final secretBox = await _aesGcm.encrypt(
        plainBytes,
        secretKey: secretKey,
        nonce: iv,
      );
      final combined = Uint8List.fromList(
          salt + iv + secretBox.cipherText + secretBox.mac.bytes);
      return combined;
    } catch (e) {
      // Logged by the calling Notifier
      throw Exception('Byte encryption failed: ${e.toString()}');
    }
  }

  Future<Uint8List> decryptBytesWithPassword(
      Uint8List encryptedBytes, String password) async {
    try {
      if (encryptedBytes.length < (16 + 12 + 0 + 16)) {
        throw Exception('Invalid encrypted data format: too short.');
      }
      final salt = encryptedBytes.sublist(0, 16);
      final iv = encryptedBytes.sublist(16, 16 + 12);
      final cipherText =
          encryptedBytes.sublist(16 + 12, encryptedBytes.length - 16);
      final macBytes = encryptedBytes.sublist(encryptedBytes.length - 16);
      final mac = Mac(macBytes);
      final secretKey = await _pbkdf2.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );
      final secretBox = SecretBox(cipherText, nonce: iv, mac: mac);
      final decryptedBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
      );
      return Uint8List.fromList(decryptedBytes);
    } on SecretBoxAuthenticationError {
      // Logged by the calling Notifier
      throw Exception(
          'Byte decryption failed: Wrong password or data corrupted.');
    } catch (e) {
      // Logged by the calling Notifier
      if (e is Exception && e.toString().contains('Authentication failed')) {
        throw Exception(
            'Byte decryption failed: Wrong password or data corrupted.');
      }
      throw Exception('Byte decryption failed: ${e.toString()}');
    }
  }
}
