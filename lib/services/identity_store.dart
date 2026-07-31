import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the recovery phrase on-device only:
///   * iOS → Keychain
///   * Android → EncryptedSharedPreferences (AES-256)
/// The phrase never leaves the device; Supabase never sees it.
class IdentityStore {
  static const _mnemonicKey = 'nyvox_identity_mnemonic';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> saveMnemonic(String mnemonic) =>
      _storage.write(key: _mnemonicKey, value: mnemonic);

  Future<String?> readMnemonic() => _storage.read(key: _mnemonicKey);

  Future<void> clear() => _storage.delete(key: _mnemonicKey);
}
