import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'crypto_service.dart';

/// All backend chat operations. Plaintext never touches Supabase —
/// messages are encrypted on-device before upload and decrypted after download.
class ChatService {
  ChatService(this._crypto);

  final SupabaseClient _client = Supabase.instance.client;
  final CryptoService _crypto;

  // ---------------------------------------------------------------- Contacts

  /// Find a user by their Account ID ("vc…"), like adding a Session ID.
  Future<Profile?> lookupAccount(String accountId) async {
    final res = await _client.rpc(
      'lookup_profile_by_account_id',
      params: {'p_account_id': accountId},
    );
    final rows = (res as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return null;
    return Profile.fromJson(rows.first);
  }

  // ------------------------------------------------------------ Conversations

  /// Open (or reuse) the 1-to-1 conversation with [peerAccountId].
  Future<String> openDm(String peerAccountId) async {
    final res = await _client.rpc(
      'create_dm_conversation',
      params: {'other_account_id': peerAccountId},
    );
    return res as String;
  }

  /// All conversations I'm in, newest activity first, with peer profile,
  /// last message, and WhatsApp-style unread count for the list UI.
  Future<List<ConversationSummary>> listConversations(String myAccountId) async {
    final memberships = await _client
        .from('conversation_members')
        .select('conversation_id, conversations(id, is_group, title, created_at)')
        .eq('account_id', myAccountId);

    final summaries = <ConversationSummary>[];

    for (final row in (memberships as List).cast<Map<String, dynamic>>()) {
      final convo = row['conversations'] as Map<String, dynamic>;
      final convoId = convo['id'] as String;
      final isGroup = convo['is_group'] as bool;

      Profile? peer;
      if (!isGroup) {
        final peerRow = await _client
            .from('conversation_members')
            .select('account_id, profiles(account_id, display_name, public_key, avatar_emoji)')
            .eq('conversation_id', convoId)
            .neq('account_id', myAccountId)
            .maybeSingle();
        if (peerRow != null) {
          peer = Profile.fromJson(peerRow['profiles'] as Map<String, dynamic>);
        }
      }

      final last = await _client
          .from('messages')
          .select()
          .eq('conversation_id', convoId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      // Unread = incoming messages with no read receipt yet.
      final unread = await _client
          .from('messages')
          .select('id')
          .eq('conversation_id', convoId)
          .neq('sender_account_id', myAccountId)
          .isFilter('read_at', null);

      summaries.add(
        ConversationSummary(
          id: convoId,
          isGroup: isGroup,
          title: convo['title'] as String?,
          createdAt: DateTime.parse(convo['created_at'] as String).toLocal(),
          peer: peer,
          lastMessage: last == null
              ? null
              : ChatMessage.fromJson(
                  last,
                  myAccountId: myAccountId,
                  plaintext: '🔒 encrypted message',
                ),
          unreadCount: (unread as List).length,
        ),
      );
    }

    summaries.sort((a, b) {
      final at = a.lastMessage?.createdAt ?? a.createdAt;
      final bt = b.lastMessage?.createdAt ?? b.createdAt;
      return bt.compareTo(at);
    });
    return summaries;
  }

  // ---------------------------------------------------------------- Messages

  /// Live stream of messages for one conversation (Supabase Realtime),
  /// decrypted on arrival, sorted oldest → newest (WhatsApp order — the
  /// stream itself can emit realtime rows out of order).
  /// Expired messages are filtered out.
  Stream<List<ChatMessage>> watchMessages({
    required String conversationId,
    required String myAccountId,
    required NyvoxIdentity identity,
    Map<String, String> publicKeysByAccount = const {},
  }) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at')
        .asyncMap((rows) async {
      final now = DateTime.now().toUtc();
      final result = <ChatMessage>[];
      for (final row in rows) {
        final expiresAt = row['expires_at'] == null
            ? null
            : DateTime.parse(row['expires_at'] as String);
        if (expiresAt != null && expiresAt.isBefore(now)) continue;

        result.add(await _decryptRow(
          row,
          myAccountId: myAccountId,
          identity: identity,
          publicKeysByAccount: publicKeysByAccount,
        ));
      }
      result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return result;
    });
  }

  /// Raw stream of every message visible to me (RLS limits this to my own
  /// conversations) — powers local notifications on the home screen.
  Stream<List<Map<String, dynamic>>> watchAllMessagesRaw() {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map((rows) => rows.cast<Map<String, dynamic>>());
  }

  Future<ChatMessage> _decryptRow(
    Map<String, dynamic> row, {
    required String myAccountId,
    required NyvoxIdentity identity,
    required Map<String, String> publicKeysByAccount,
  }) async {
    String? plaintext;
    try {
      final senderId = row['sender_account_id'] as String;
      // The DM shared secret is X25519(my secret key, PEER's public key).
      // For messages from the peer, decrypt with the sender's (= peer's) key.
      // For MY OWN messages, the secret was ALSO derived with the peer's key —
      // using my own key here derives the wrong secret and AES-GCM fails.
      final String? decryptWithKey;
      if (senderId == myAccountId) {
        final others = publicKeysByAccount.entries
            .where((e) => e.key != myAccountId);
        decryptWithKey = others.isEmpty ? null : others.first.value;
      } else {
        decryptWithKey = publicKeysByAccount[senderId];
      }
      if (decryptWithKey != null) {
        plaintext = await _crypto.decryptText(
          myKeyPair: identity.keyPair,
          senderPublicKeyHex: decryptWithKey,
          ciphertextB64: row['ciphertext'] as String,
          nonceB64: row['nonce'] as String,
        );
      }
    } catch (_) {
      plaintext = null;
    }
    return ChatMessage.fromJson(row, myAccountId: myAccountId, plaintext: plaintext);
  }

  /// Encrypt [text] with the DM shared secret — X25519(my secret key, peer's
  /// public key) — and upload only the ciphertext. Both sides derive the same
  /// secret, so either can decrypt.
  Future<void> sendMessage({
    required String conversationId,
    required NyvoxIdentity identity,
    required Profile peer,
    required String text,
    Duration? disappearAfter,
  }) async {
    final payload = await _crypto.encryptText(
      myKeyPair: identity.keyPair,
      peerPublicKeyHex: peer.publicKey,
      plaintext: text,
    );

    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_account_id': identity.accountId,
      'ciphertext': payload.ciphertextB64,
      'nonce': payload.nonceB64,
      'expires_at': disappearAfter == null
          ? null
          : DateTime.now().toUtc().add(disappearAfter).toIso8601String(),
    });
  }

  Future<void> markRead(String messageId) async {
    await _client
        .from('messages')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', messageId)
        .isFilter('read_at', null);
  }

  /// Mark every incoming message in a conversation as read — clears the
  /// unread badge and sends read receipts to the sender.
  Future<void> markConversationRead(
      String conversationId, String myAccountId) async {
    await _client
        .from('messages')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('conversation_id', conversationId)
        .neq('sender_account_id', myAccountId)
        .isFilter('read_at', null);
  }

  /// Delete a single message ("delete for everyone").
  Future<void> deleteMessage(String messageId) async {
    await _client.from('messages').delete().eq('id', messageId);
  }

  /// Remove expired messages from the server (belt-and-braces alongside the
  /// optional pg_cron job in schema.sql).
  Future<void> purgeExpired() async {
    await _client
        .from('messages')
        .delete()
        .lt('expires_at', DateTime.now().toUtc().toIso8601String());
  }
}
