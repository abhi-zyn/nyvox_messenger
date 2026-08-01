import 'package:bip39/bip39.dart' as bip39;
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

/// All encryption happens on-device with libsodium-grade primitives:
/// X25519 for shared secrets, AES-256-GCM for messages and attachments.
class CryptoService {
  final _x25519 = X25519();
  final _aesGcm = AesGcm.with256bits();

  ({List<int> privateKey, List<int> publicKey}) identityFromMnemonic(
      String mnemonic) {
    final seed = bip39.mnemonicToSeed(mnemonic);
    final privateKey = seed.sublist(0, 32);
    return (privateKey: privateKey, publicKey: const []);
  }

  String generateMnemonic() => bip39.generateMnemonic(strength: 128);

  Future<SimpleKeyPair> _keyPairFromSeed(List<int> privateKey) async {
    return _x25519.newKeyPairFromSeed(privateKey);
  }

  Future<List<int>> publicKeyFromPrivate(List<int> privateKey) async {
    final kp = await _keyPairFromSeed(privateKey);
    final pub = await kp.extractPublicKey();
    return pub.bytes;
  }

  Future<SecretKey> sharedSecret(
      List<int> myPrivateKey, List<int> theirPublicKey) async {
    final kp = await _keyPairFromSeed(myPrivateKey);
    return _x25519.sharedSecretKey(
      keyPair: kp,
      remotePublicKey: SimplePublicKey(theirPublicKey, type: KeyPairType.x25519),
    );
  }

  Future<SecretBox> encryptWithSecret(SecretKey secret, List<int> data) =>
      _aesGcm.encrypt(data, secretKey: secret);

  Future<List<int>> decryptWithSecret(SecretKey secret, SecretBox box) =>
      _aesGcm.decrypt(box, secretKey: secret);

  // ---- Group key support (one AES key per group, distributed per member) ----

  Future<List<int>> generateGroupKeyBytes() async =>
      (await _aesGcm.newSecretKey()).extractBytes();

  Future<SecretBox> encryptWithKeyBytes(
          List<int> keyBytes, List<int> data) =>
      _aesGcm.encrypt(data, secretKey: SecretKey(keyBytes));

  Future<List<int>> decryptWithKeyBytes(List<int> keyBytes, SecretBox box) =>
      _aesGcm.decrypt(box, secretKey: SecretKey(keyBytes));

  SecretKey secretKeyFromBytes(List<int> bytes) => SecretKey(bytes);

  String randomId() => sha256
      .convert(List.generate(
          32, (i) => (DateTime.now().microsecondsSinceEpoch + i * 7919) % 256))
      .toString()
      .substring(0, 32);
}
