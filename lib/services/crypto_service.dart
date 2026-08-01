import 'dart:convert';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';

/// A Nyvox identity: an X25519 keypair derived from a BIP-39 recovery
/// phrase. The Account ID is "vc" + hex(public key) — it reveals nothing
/// about the user, exactly like a Session ID.
class NyvoxIdentity {
  const NyvoxIdentity({
    required this.mnemonic,
    required this.keyPair,
    required this.publicKeyHex,
    required this.accountId,
  });

  /// BIP-39 recovery phrase (12 words). Stored only on-device, in secure storage.
  final String mnemonic;
  final SimpleKeyPair keyPair;
  final String publicKeyHex;
  final String accountId;
}

class EncryptedPayload {
  const EncryptedPayload({required this.ciphertextB64, required this.nonceB64});

  /// base64( ciphertext || 16-byte MAC )
  final String ciphertextB64;

  /// base64( 12-byte AES-GCM nonce )
  final String nonceB64;
}

/// End-to-end encryption:
///   * X25519 Diffie–Hellman between the two devices derives a shared secret
///     that never travels over the network.
///   * Every message is encrypted with AES-256-GCM under a fresh random nonce.
///   * The server only ever stores ciphertext + nonce.
class CryptoService {
  final X25519 _x25519 = X25519();
  final AesGcm _aes = AesGcm.with256bits();
  final Map<String, SecretKey> _sharedSecretCache = {};

  Future<NyvoxIdentity> newIdentity() async {
    final mnemonic = bip39.generateMnemonic();
    return identityFromMnemonic(mnemonic);
  }

  Future<NyvoxIdentity> identityFromMnemonic(String mnemonic) async {
    final normalized =
        mnemonic.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');
    if (!bip39.validateMnemonic(normalized)) {
      throw ArgumentError('That recovery phrase is not valid.');
    }
    final fullSeed = bip39.mnemonicToSeed(normalized); // 64 bytes
    final seed = Uint8List.fromList(fullSeed.sublist(0, 32));
    final keyPair = await _x25519.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    final publicKeyHex = hex.encode(publicKey.bytes);
    return NyvoxIdentity(
      mnemonic: normalized,
      keyPair: keyPair,
      publicKeyHex: publicKeyHex,
      accountId: 'vc$publicKeyHex',
    );
  }

  Future<SecretKey> _sharedSecret(
      SimpleKeyPair mine, String peerPublicKeyHex) async {
    final cached = _sharedSecretCache[peerPublicKeyHex];
    if (cached != null) return cached;
    final remote = SimplePublicKey(
      hex.decode(peerPublicKeyHex),
      type: KeyPairType.x25519,
    );
    final secret = await _x25519.sharedSecretKey(
      keyPair: mine,
      remotePublicKey: remote,
    );
    _sharedSecretCache[peerPublicKeyHex] = secret;
    return secret;
  }

  Future<EncryptedPayload> encryptBytes({
    required SimpleKeyPair myKeyPair,
    required String peerPublicKeyHex,
    required Uint8List data,
  }) async {
    final secret = await _sharedSecret(myKeyPair, peerPublicKeyHex);
    final box = await _aes.encrypt(data, secretKey: secret);
    final combined = <int>[...box.cipherText, ...box.mac.bytes];
    return EncryptedPayload(
      ciphertextB64: base64Encode(combined),
      nonceB64: base64Encode(box.nonce),
    );
  }

  Future<EncryptedPayload> encryptText({
    required SimpleKeyPair myKeyPair,
    required String peerPublicKeyHex,
    required String plaintext,
  }) =>
      encryptBytes(
        myKeyPair: myKeyPair,
        peerPublicKeyHex: peerPublicKeyHex,
        data: Uint8List.fromList(utf8.encode(plaintext)),
      );

  Future<Uint8List> decryptBytes({
    required SimpleKeyPair myKeyPair,
    required String senderPublicKeyHex,
    required String ciphertextB64,
    required String nonceB64,
  }) async {
    final secret = await _sharedSecret(myKeyPair, senderPublicKeyHex);
    final combined = base64Decode(ciphertextB64);
    final cipherBytes = combined.sublist(0, combined.length - 16);
    final macBytes = combined.sublist(combined.length - 16);
    final plainBytes = await _aes.decrypt(
      SecretBox(
        cipherBytes,
        nonce: base64Decode(nonceB64),
        mac: Mac(macBytes),
      ),
      secretKey: secret,
    );
    return Uint8List.fromList(plainBytes);
  }

  Future<String> decryptText({
    required SimpleKeyPair myKeyPair,
    required String senderPublicKeyHex,
    required String ciphertextB64,
    required String nonceB64,
  }) async =>
      utf8.decode(await decryptBytes(
        myKeyPair: myKeyPair,
        senderPublicKeyHex: senderPublicKeyHex,
        ciphertextB64: ciphertextB64,
        nonceB64: nonceB64,
      ));

  // ------------------------- Group keys -------------------------

  /// A fresh random 32-byte AES key for a group conversation. The creator
  /// encrypts a copy for every member over the normal pairwise channel.
  Future<Uint8List> generateGroupKeyBytes() async =>
      Uint8List.fromList(await (await _aes.newSecretKey()).extractBytes());

  /// Encrypt bytes with a raw group key (no X25519 involved).
  Future<EncryptedPayload> encryptWithKeyBytes({
    required Uint8List keyBytes,
    required Uint8List data,
  }) async {
    final box = await _aes.encrypt(data, secretKey: SecretKey(keyBytes));
    final combined = <int>[...box.cipherText, ...box.mac.bytes];
    return EncryptedPayload(
      ciphertextB64: base64Encode(combined),
      nonceB64: base64Encode(box.nonce),
    );
  }

  Future<Uint8List> decryptWithKeyBytes({
    required Uint8List keyBytes,
    required String ciphertextB64,
    required String nonceB64,
  }) async {
    final combined = base64Decode(ciphertextB64);
    final cipherBytes = combined.sublist(0, combined.length - 16);
    final macBytes = combined.sublist(combined.length - 16);
    final plain = await _aes.decrypt(
      SecretBox(cipherBytes, nonce: base64Decode(nonceB64), mac: Mac(macBytes)),
      secretKey: SecretKey(keyBytes),
    );
    return Uint8List.fromList(plain);
  }
}
