import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models.dart';
import '../state/app_session.dart';
import 'crypto_service.dart';
import 'supabase_client.dart';

/// Messaging: end-to-end encrypted DMs and groups, view-once attachments
/// (images + files), voice notes, synced disappearing timers, read receipts.
class ChatService {
  final _crypto = CryptoService();
  SupabaseClient get _client => NyvoxSupabase.client;

  // ------------------------- conversations -------------------------

  Stream<List<Map<String, dynamic>>> watchConversationRows(String accountId) {
    return _client
        .from('conversation_members')
        .stream(primaryKey: ['conversation_id', 'account_id'])
        .eq('account_id', accountId);
  }

  Future<ConversationSummary?> loadConversationSummary(
      String conversationId, String myAccountId) async {
    final convo = await _client
        .from('conversations')
        .select('id, is_group, title')
        .eq('id', conversationId)
        .maybeSingle();
    if (convo == null) return null;
    String title = convo['title'] as String? ?? 'Chat';
    if (!(convo['is_group'] as bool? ?? false)) {
      final members = await _client
          .from('conversation_members')
          .select('account_id')
          .eq('conversation_id', conversationId)
          .neq('account_id', myAccountId)
          .limit(1);
      if (members.isNotEmpty) {
        final profile = await _client
            .from('profiles')
            .select('display_name')
            .eq('account_id', members.first['account_id'])
            .maybeSingle();
        title = profile?['display_name'] as String? ?? 'Anonymous';
      }
    }
    return ConversationSummary(
      id: conversationId,
      title: title,
      isGroup: convo['is_group'] as bool? ?? false,
    );
  }

  /// Watch a single conversation (carries the synced disappear timer).
  Stream<ConversationInfo> watchConversation(String conversationId) {
    return _client
        .from('conversations')
        .stream(primaryKey: ['id'])
        .eq('id', conversationId)
        .map((rows) => ConversationInfo.fromRow(rows.first));
  }

  /// Set (or clear, with null) the conversation's disappearing timer.
  /// Stored server-side, so both members stay in sync via realtime.
  Future<void> updateConversationTimer(
      String conversationId, int? seconds) async {
    await _client
        .from('conversations')
        .update({'disappear_seconds': seconds}).eq('id', conversationId);
  }

  Future<String> getOrCreateDm(String myAccountId, String peerAccountId) {
    return _client
        .rpc('create_dm_conversation',
            params: {'a': myAccountId, 'b': peerAccountId})
        .then((v) => v as String);
  }

  // ------------------------- groups -------------------------

  /// Create a group: one random AES key, encrypted separately for every
  /// member (including the creator) with their pairwise X25519 secret.
  Future<String> createGroupConversation({
    required String title,
    required List<Profile> members,
    required AppSession session,
  }) async {
    final keyBytes = await _crypto.generateGroupKeyBytes();
    final all = [...members, session.profile];
    final envelopes = <Map<String, String>>[];
    for (final m in all) {
      final secret = await _crypto.sharedSecret(
          session.identity.privateKey, m.publicKey);
      final box = await _crypto.encryptWithKeyBytes(
          await secret.extractBytes(), keyBytes);
      // Prefix the creator id so members know whose public key unlocks this.
      envelopes.add({
        'account_id': m.accountId,
        'encrypted_key':
            '${session.profile.accountId}:${base64Encode(box.concatenation())}',
        'nonce': '',
      });
    }
    return _client.rpc('create_group_conversation', params: {
      'p_title': title,
      'p_member_ids': all.map((m) => m.accountId).toList(),
      'p_envelopes': envelopes,
    }).then((v) => v as String);
  }

  /// Fetch + decrypt this device's copy of the group key.
  Future<List<int>> getGroupKey(
      String conversationId, AppSession session) async {
    final row = await _client
        .from('group_keys')
        .select('encrypted_key')
        .eq('conversation_id', conversationId)
        .eq('account_id', session.profile.accountId)
        .maybeSingle();
    if (row == null) throw StateError('No group key for you in this group');
    final raw = row['encrypted_key'] as String;
    final sep = raw.indexOf(':');
    final creatorId = raw.substring(0, sep);
    final box =
        SecretBox.fromConcatenation(base64Decode(raw.substring(sep + 1)));
    final creator = await lookupProfile(creatorId);
    if (creator == null) throw StateError('Group creator profile missing');
    final secret = await _crypto.sharedSecret(
        session.identity.privateKey, creator.publicKey);
    return _crypto.decryptWithSecret(secret, box);
  }

  Future<List<Profile>> listMembersWithProfiles(String conversationId) async {
    final members = await _client
        .from('conversation_members')
        .select('account_id')
        .eq('conversation_id', conversationId);
    final profiles = <Profile>[];
    for (final m in members) {
      final p = await lookupProfile(m['account_id'] as String);
      if (p != null) profiles.add(p);
    }
    return profiles;
  }

  // ------------------------- profiles -------------------------

  Future<Profile?> lookupProfile(String accountId) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('account_id', accountId.trim())
        .maybeSingle();
    if (row == null) return null;
    return Profile.fromRow(row);
  }

  // ------------------------- messages -------------------------

  Stream<List<ChatMessage>> watchMessages({
    required String conversationId,
    required Profile peer,
    required AppSession session,
  }) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at')
        .asyncMap((rows) async {
      final secret = await _crypto.sharedSecret(
          session.identity.privateKey, peer.publicKey);
      final result = <ChatMessage>[];
      final seen = <String>{};
      for (final row in rows) {
        // Realtime can transiently emit a freshly inserted row twice.
        if (!seen.add(row['id'] as String)) continue;
        final expiresAt = row['expires_at'] == null
            ? null
            : DateTime.parse(row['expires_at'] as String);
        if (expiresAt != null &&
            DateTime.now().toUtc().isAfter(expiresAt)) {
          continue;
        }
        final msg = ChatMessage.fromRow(row);
        if (!msg.hasAttachment) {
          msg.plaintext = await _decryptText(msg, secret);
        }
        result.add(msg);
      }
      result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return result;
    });
  }

  Stream<List<ChatMessage>> watchGroupMessages({
    required String conversationId,
    required List<int> groupKey,
  }) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at')
        .asyncMap((rows) async {
      final result = <ChatMessage>[];
      final seen = <String>{};
      for (final row in rows) {
        if (!seen.add(row['id'] as String)) continue;
        final expiresAt = row['expires_at'] == null
            ? null
            : DateTime.parse(row['expires_at'] as String);
        if (expiresAt != null &&
            DateTime.now().toUtc().isAfter(expiresAt)) {
          continue;
        }
        final msg = ChatMessage.fromRow(row);
        if (!msg.hasAttachment) {
          msg.plaintext = await _decryptTextWithKey(msg, groupKey);
        }
        result.add(msg);
      }
      result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return result;
    });
  }

  Future<String?> _decryptText(ChatMessage msg, SecretKey secret) async {
    try {
      final bytes = await _decryptBytes(msg.ciphertext, msg.nonce, secret);
      return utf8.decode(bytes);
    } catch (_) {
      return '⚠️ could not decrypt';
    }
  }

  Future<String?> _decryptTextWithKey(ChatMessage msg, List<int> key) async {
    try {
      final bytes = await _decryptBytesWithKey(msg.ciphertext, msg.nonce, key);
      return utf8.decode(bytes);
    } catch (_) {
      return '⚠️ could not decrypt';
    }
  }

  /// Handles both legacy rows (nonce in column) and concatenation rows.
  Future<List<int>> _decryptBytes(
      String ciphertextB64, String nonce, SecretKey secret) async {
    final box = nonce.isEmpty
        ? SecretBox.fromConcatenation(base64Decode(ciphertextB64))
        : SecretBox(base64Decode(ciphertextB64),
            nonce: base64Decode(nonce));
    return _crypto.decryptWithSecret(secret, box);
  }

  Future<List<int>> _decryptBytesWithKey(
      String ciphertextB64, String nonce, List<int> key) async {
    final box = nonce.isEmpty
        ? SecretBox.fromConcatenation(base64Decode(ciphertextB64))
        : SecretBox(base64Decode(ciphertextB64),
            nonce: base64Decode(nonce));
    return _crypto.decryptWithKeyBytes(key, box);
  }

  Future<SecretKey> _secretFor(AppSession session, Profile peer) =>
      _crypto.sharedSecret(session.identity.privateKey, peer.publicKey);

  Future<void> sendText({
    required String conversationId,
    required AppSession session,
    required Profile? peer,
    List<int>? groupKey,
    required String text,
    int? disappearSeconds,
  }) async {
    final box = groupKey != null
        ? await _crypto.encryptWithKeyBytes(groupKey, utf8.encode(text))
        : await _crypto.encryptWithSecret(
            await _secretFor(session, peer!), utf8.encode(text));
    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_account_id': session.profile.accountId,
      'ciphertext': base64Encode(box.concatenation()),
      'nonce': '',
      if (disappearSeconds != null)
        'expires_at': DateTime.now()
            .toUtc()
            .add(Duration(seconds: disappearSeconds))
            .toIso8601String(),
    });
  }

  Future<void> sendViewOnceAttachment({
    required String conversationId,
    required AppSession session,
    required Profile? peer,
    List<int>? groupKey,
    required List<int> bytes,
    required String type, // image | file | voice
    String? name,
    int? size,
  }) async {
    final box = groupKey != null
        ? await _crypto.encryptWithKeyBytes(groupKey, bytes)
        : await _crypto.encryptWithSecret(
            await _secretFor(session, peer!), bytes);
    final path =
        '${session.profile.accountId}/${_crypto.randomId()}.enc';
    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_account_id': session.profile.accountId,
      'ciphertext': '',
      'nonce': '',
      'attachment_path': path,
      'attachment_nonce': '',
      'attachment_type': type,
      'attachment_name': name,
      'attachment_size': size ?? bytes.length,
    });
    await _client.storage.from('chat-media').uploadBinary(
        path, box.concatenation(),
        fileOptions: const FileOptions(upsert: true));
  }

  /// Download + decrypt an attachment. View-once items (image/file) are
  /// destroyed everywhere right after decryption; voice notes persist.
  Future<List<int>> openAttachment({
    required ChatMessage message,
    required AppSession session,
    Profile? peer,
    List<int>? groupKey,
  }) async {
    if (message.attachmentPath == null) throw StateError('No attachment');
    final packed = await _client.storage
        .from('chat-media')
        .download(message.attachmentPath!);
    final box = SecretBox.fromConcatenation(packed);
    final bytes = groupKey != null
        ? await _crypto.decryptWithKeyBytes(groupKey, box)
        : await _crypto.decryptWithSecret(
            await _secretFor(session, peer!), box);
    if (message.isViewOnce) {
      await _client.storage
          .from('chat-media')
          .remove([message.attachmentPath!]);
      await _client.from('messages').delete().eq('id', message.id);
    }
    return bytes;
  }

  Future<void> markConversationRead(
      String conversationId, String myAccountId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client
        .from('messages')
        .update({'read_at': now})
        .eq('conversation_id', conversationId)
        .neq('sender_account_id', myAccountId)
        .isFilter('read_at', null);
  }

  Future<List<ChatMessage>> fetchLatestPerConversation(
      String myAccountId) async {
    final rows = await _client
        .from('messages')
        .select()
        .order('created_at', ascending: false)
        .limit(500);
    final byId = <String, ChatMessage>{};
    final seen = <String>{};
    for (final r in rows) {
      final cid = r['conversation_id'] as String;
      if (seen.contains(cid)) continue;
      seen.add(cid);
      byId[cid] = ChatMessage.fromRow(r);
    }
    return byId.values.toList();
  }

  Future<int> unreadCount(String conversationId, String myAccountId) async {
    final rows = await _client
        .from('messages')
        .select('id')
        .eq('conversation_id', conversationId)
        .neq('sender_account_id', myAccountId)
        .isFilter('read_at', null);
    return rows.length;
  }
}
