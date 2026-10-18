import 'package:elaa_shared/elaa_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pointycastle/export.dart' as pc;
import 'dart:convert';

class HubSecurityManager {
  static const String _privKeyPref = 'hub_private_key_json';
  static const String _pubKeyPref = 'hub_public_key_json';

  static Future<void> initializeKeys() async {
    final prefs = await SharedPreferences.getInstance();
    
    if (!prefs.containsKey(_privKeyPref)) {
      final pair = EncryptionEngine.generateRSAKeyPair();
      
      final pubMap = {
        'modulus': pair.publicKey.modulus.toString(),
        'exponent': pair.publicKey.exponent.toString()
      };
      
      final privMap = {
        'modulus': pair.privateKey.modulus.toString(),
        'privateExponent': pair.privateKey.privateExponent.toString(),
        'p': pair.privateKey.p.toString(),
        'q': pair.privateKey.q.toString(),
      };
      
      await prefs.setString(_pubKeyPref, jsonEncode(pubMap));
      await prefs.setString(_privKeyPref, jsonEncode(privMap));
    }
  }

  static Future<pc.RSAPublicKey> getPublicKey() async {
    await initializeKeys();
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_pubKeyPref)!;
    final map = jsonDecode(jsonStr);
    return pc.RSAPublicKey(
      BigInt.parse(map['modulus']),
      BigInt.parse(map['exponent']),
    );
  }

  static Future<pc.RSAPrivateKey> getPrivateKey() async {
    await initializeKeys();
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_privKeyPref)!;
    final map = jsonDecode(jsonStr);
    return pc.RSAPrivateKey(
      BigInt.parse(map['modulus']),
      BigInt.parse(map['privateExponent']),
      BigInt.parse(map['p']),
      BigInt.parse(map['q']),
    );
  }
}
