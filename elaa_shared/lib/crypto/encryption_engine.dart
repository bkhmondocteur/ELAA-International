import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/export.dart' as pc;
import 'package:pointycastle/api.dart' as pc_api;

class EncryptionEngine {
  /// Génère une paire de clés RSA (Publique/Privée) pour un utilisateur (Hub ou Médecin)
  static pc.AsymmetricKeyPair<pc.RSAPublicKey, pc.RSAPrivateKey> generateRSAKeyPair() {
    final secureRandom = pc.SecureRandom('Fortuna')
      ..seed(pc.KeyParameter(
          Uint8List.fromList(List.generate(32, (_) => Random.secure().nextInt(255)))));

    final keyGen = pc.RSAKeyGenerator()
      ..init(pc.ParametersWithRandom(
          pc.RSAKeyGeneratorParameters(BigInt.parse('65537'), 1024, 12), secureRandom));

    final pair = keyGen.generateKeyPair();
    return pc.AsymmetricKeyPair<pc.RSAPublicKey, pc.RSAPrivateKey>(
        pair.publicKey as pc.RSAPublicKey, pair.privateKey as pc.RSAPrivateKey);
  }

  /// Décode une clé publique RSA depuis son format JSON encodé en Base64
  static pc.RSAPublicKey parsePublicKeyFromBase64(String base64String) {
    final jsonStr = utf8.decode(base64Decode(base64String));
    final map = jsonDecode(jsonStr);
    return pc.RSAPublicKey(
      BigInt.parse(map['modulus']),
      BigInt.parse(map['exponent']),
    );
  }

  /// Décode une clé privée RSA depuis son format JSON
  static pc.RSAPrivateKey parsePrivateKeyFromJson(String jsonStr) {
    final map = jsonDecode(jsonStr);
    return pc.RSAPrivateKey(
      BigInt.parse(map['modulus']),
      BigInt.parse(map['privateExponent']),
      BigInt.parse(map['p']),
      BigInt.parse(map['q']),
    );
  }

  /// Chiffre une donnée avec une clé publique RSA (OAEP avec SecureRandom + Fallback PKCS1)
  static String encryptRSA(String data, pc.RSAPublicKey publicKey) {
    try {
      final secureRandom = pc.SecureRandom('Fortuna')
        ..seed(pc.KeyParameter(
            Uint8List.fromList(List.generate(32, (_) => Random.secure().nextInt(255)))));
      final encryptor = pc.OAEPEncoding(pc.RSAEngine())
        ..init(true, pc.ParametersWithRandom(pc.PublicKeyParameter<pc.RSAPublicKey>(publicKey), secureRandom));
      final encrypted = encryptor.process(Uint8List.fromList(utf8.encode(data)));
      return base64Encode(encrypted);
    } catch (e) {
      final secureRandom = pc.SecureRandom('Fortuna')
        ..seed(pc.KeyParameter(
            Uint8List.fromList(List.generate(32, (_) => Random.secure().nextInt(255)))));
      final encryptor = pc.PKCS1Encoding(pc.RSAEngine())
        ..init(true, pc.ParametersWithRandom(pc.PublicKeyParameter<pc.RSAPublicKey>(publicKey), secureRandom));
      final encrypted = encryptor.process(Uint8List.fromList(utf8.encode(data)));
      return base64Encode(encrypted);
    }
  }

  /// Déchiffre une donnée avec une clé privée RSA (OAEP + Fallback PKCS1)
  static String decryptRSA(String encryptedData, pc.RSAPrivateKey privateKey) {
    try {
      final decryptor = pc.OAEPEncoding(pc.RSAEngine())
        ..init(false, pc.PrivateKeyParameter<pc.RSAPrivateKey>(privateKey));
      final decrypted = decryptor.process(base64Decode(encryptedData));
      return utf8.decode(decrypted);
    } catch (e) {
      final decryptor = pc.PKCS1Encoding(pc.RSAEngine())
        ..init(false, pc.PrivateKeyParameter<pc.RSAPrivateKey>(privateKey));
      final decrypted = decryptor.process(base64Decode(encryptedData));
      return utf8.decode(decrypted);
    }
  }

  /// Génère une clé AES-256 (32 octets) pour une consultation spécifique
  static encrypt.Key generateConsultationKey() {
    return encrypt.Key.fromSecureRandom(32);
  }

  /// Chiffre des données (JSON, texte) avec la clé AES de la consultation
  static String encryptDataAES(String data, encrypt.Key key) {
    final String dataToEncrypt = data.isEmpty ? ' ' : data;
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final encrypted = encrypter.encrypt(dataToEncrypt, iv: iv);
    // On concatène IV + données chiffrées pour le stockage
    return '${iv.base64}:${encrypted.base64}';
  }

  /// Déchiffre des données avec la clé AES de la consultation
  static String decryptDataAES(String encryptedDataString, encrypt.Key key) {
    final parts = encryptedDataString.split(':');
    if (parts.length != 2) throw Exception('Format de données chiffrées invalide');
    final iv = encrypt.IV.fromBase64(parts[0]);
    final encrypted = encrypt.Encrypted.fromBase64(parts[1]);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    return encrypter.decrypt(encrypted, iv: iv);
  }

  /// Dérive une clé AES à partir du code PIN du médecin (PBKDF2)
  static encrypt.Key deriveKeyFromPin(String pin, String salt) {
    final derivator = pc.KeyDerivator('SHA-256/HMAC/PBKDF2')
      ..init(pc.Pbkdf2Parameters(Uint8List.fromList(utf8.encode(salt)), 10000, 32));
    final keyBytes = derivator.process(Uint8List.fromList(utf8.encode(pin)));
    return encrypt.Key(keyBytes);
  }
}
