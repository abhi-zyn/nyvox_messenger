import 'package:supabase_flutter/supabase_flutter.dart';

import 'crypto_service.dart';
import 'identity_store.dart';

/// Everything the app needs to operate: the on-device identity plus the
/// account id that other users see.
class AppSession {
  const AppSession({required this.identity});

  final NyvoxIdentity identity;
  String get accountId => identity.accountId;
}

/// Session-style authentication:
///   * No email, no phone number. The device identity (X25519 keypair,
///     backed up as a recovery phrase) IS the account.
///   * Behind the scenes we use Supabase *anonymous* sign-in purely as a
///     transport credential for Row Level Security. It is linked to the
///     Account ID through the device_auth table, so restoring your phrase
///     on a new device brings back the same identity.
class AuthService {
  final SupabaseClient _client = Supabase.instance.client;
  final CryptoService _crypto = CryptoService();
  final IdentityStore _store = IdentityStore();

  /// Restore the identity saved on this device (if any) and make sure the
  /// backend session matches it.
  Future<AppSession?> loadSavedSession() async {
    final mnemonic = await _store.readMnemonic();
    if (mnemonic == null) return null;
    try {
      final identity = await _crypto.identityFromMnemonic(mnemonic);
      await _ensureBackendSession(identity);
      return AppSession(identity: identity);
    } catch (_) {
      // Corrupt phrase or offline — let the user re-onboard.
      return null;
    }
  }

  /// Create a brand-new identity (used by "Create account").
  Future<AppSession> createAccount(String displayName) async {
    final identity = await _crypto.newIdentity();
    await _store.saveMnemonic(identity.mnemonic);
    await _ensureBackendSession(identity, displayName: displayName);
    return AppSession(identity: identity);
  }

  /// Restore an existing identity from its 12-word recovery phrase.
  Future<AppSession> restoreAccount(String mnemonic) async {
    final identity = await _crypto.identityFromMnemonic(mnemonic);
    await _store.saveMnemonic(identity.mnemonic);
    await _ensureBackendSession(identity);
    return AppSession(identity: identity);
  }

  /// Anonymous sign-in, profile creation, and device linking — all idempotent.
  Future<void> _ensureBackendSession(
    NyvoxIdentity identity, {
    String? displayName,
  }) async {
    if (_client.auth.currentSession == null) {
      await _client.auth.signInAnonymously();
    }

    final accountId = identity.accountId;

    // 1. Claim the profile row if this Account ID isn't registered yet.
    final existing = await _client
        .from('profiles')
        .select('account_id, display_name')
        .eq('account_id', accountId)
        .maybeSingle();

    if (existing == null) {
      await _client.from('profiles').insert({
        'account_id': accountId,
        'public_key': identity.publicKeyHex,
        'display_name':
            (displayName == null || displayName.trim().isEmpty)
                ? 'Anonymous'
                : displayName.trim(),
      });
    }

    // 2. Link this device's anonymous auth session to the Account ID.
    final authUid = _client.auth.currentUser!.id;
    await _client.from('device_auth').upsert({
      'auth_uid': authUid,
      'account_id': accountId,
    });
  }

  /// Update the public display name for [accountId] (only the identity's own
  /// devices may do this — enforced by RLS).
  Future<void> updateDisplayName(String accountId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _client
        .from('profiles')
        .update({'display_name': trimmed})
        .eq('account_id', accountId);
  }

  /// Wipe this device: remove the local identity and sign out.
  Future<void> signOutAndWipe() async {
    await _store.clear();
    await _client.auth.signOut();
  }
}
