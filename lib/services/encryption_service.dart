import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:convert';

class EncryptionService {
  static encrypt.Key _generateKey(String roomId) {
    final keyString = roomId.padRight(32, '0').substring(0, 32);
    return encrypt.Key.fromUtf8(keyString);
  }
  static String encryptMessage(String plainText, String roomId) {
    final key = _generateKey(roomId);
    final iv = encrypt.IV.fromSecureRandom(16);  // 16-byte IV
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    final combined = iv.bytes + encrypted.bytes;
    return base64.encode(combined);
  }

  static String decryptMessage(String combinedBase64, String roomId) {
    try {
      final key = _generateKey(roomId);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final combinedBytes = base64.decode(combinedBase64);
      final iv = encrypt.IV(combinedBytes.sublist(0, 16));
      final encrypted =
      encrypt.Encrypted(combinedBytes.sublist(16));
      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      return 'Decryption Failed';
    }
  }
}