import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'chat_media_service.dart';
import 'crypto_service.dart';

/// All backend chat operations. Plaintext never touches Supabase —
/// messages are encrypted on-device before upload and decrypted after download.
class ChatService {
  ChatService(this._crypto);

  final SupabaseClient _client = Supabase.instance.client;
  final CryptoService _crypto;
  final ChatMediaService _media = ChatMediaService();

  Future<Profile?> lookupAccount(String accountId) async {
    final res = await _client.rpc(
      'lookup_profile_by_account_id',
      params: {'p_account_id': accountId},
    );
    final rows = (res as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return null;
    return Profile.fromJson(rows.first);
  }

  Future<String> openDm(String peerAccountId) async {
    final res = await _client.rpc(
      'create_dm_conversation',
      params: {'other_account_id': peerAccountId},
    );
    return res as String;
  }

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
            .select('account_id, profiles(account_id, display_name, public_key, avatar_emoji, avatar_url)')
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
          .or('high_security.eq.false,sender_account_id.neq.$myAccountId')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

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
                  plaintext: last['attachment_path'] != null
                      ? '📷 Photo'
                      : '🔒 encrypted message',
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

  /// Live conversation row — carries the synced disappearing timer.
  Stream<ConversationInfo> watchConversation(String conversationId) {
    return _client
        .from('conversations')
        .stream(primaryKey: ['id'])
        .eq('id', conversationId)
        .map((rows) => ConversationInfo.fromJson(rows.first));
  }

  Future<void> updateConversationTimer(
      String conversationId, int? seconds) async {
    await _client
        .from('conversations')
        .update({'disappear_seconds': seconds}).eq('id', conversationId);
  }

  Future<void> updateConversationHighSecurity(
      String conversationId, bool enabled) async {
    await _client
        .from('conversations')
        .update({'high_security': enabled}).eq('id', conversationId);
  }

  Future<List<Profile>> listMemberProfiles(String conversationId) async {
    final rows = await _client
        .from('conversation_members')
        .select('profiles(account_id, display_name, public_key, avatar_emoji, avatar_url)')
        .eq('conversation_id', conversationId);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map((r) => Profile.fromJson(r['profiles'] as Map<String, dynamic>))
        .toList();
  }

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
      final seen = <String>{};
      for (final row in rows) {
        // Realtime can transiently emit a freshly inserted row twice.
        if (!seen.add(row['id'] as String)) continue;
        if ((row['high_security'] as bool? ?? false) &&
            row['sender_account_id'] == myAccountId) {
          continue;
        }
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
      if (row['attachment_path'] != null) {
        return ChatMessage.fromJson(row,
            myAccountId: myAccountId, plaintext: null);
      }
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

  Future<void> sendMessage({
    required String conversationId,
    required NyvoxIdentity identity,
    required Profile peer,
    required String text,
    Duration? disappearAfter,
    bool highSecurity = false,
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
      'high_security': highSecurity,
      'expires_at': disappearAfter == null
          ? null
          : DateTime.now().toUtc().add(disappearAfter).toIso8601String(),
    });
  }

  Future<void> sendViewOnceImage({
    required String conversationId,
    required NyvoxIdentity identity,
    required Profile peer,
    required Uint8List compressedJpg,
    bool highSecurity = false,
  }) =>
      sendViewOnceAttachment(
        conversationId: conversationId,
        identity: identity,
        peer: peer,
        bytes: compressedJpg,
        type: 'image',
        highSecurity: highSecurity,
      );

  Future<void> sendViewOnceAttachment({
    required String conversationId,
    required NyvoxIdentity identity,
    required Profile peer,
    required Uint8List bytes,
    required String type,
    String? name,
    int? size,
    bool highSecurity = false,
  }) async {
    final payload = await _crypto.encryptBytes(
      myKeyPair: identity.keyPair,
      peerPublicKeyHex: peer.publicKey,
      data: bytes,
    );
    final path =
        '$conversationId/${identity.accountId}-${DateTime.now().millisecondsSinceEpoch}.bin';
    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_account_id': identity.accountId,
      'ciphertext': '',
      'nonce': '',
      'attachment_path': path,
      'attachment_nonce': payload.nonceB64,
      'attachment_type': type,
      'attachment_name': name,
      'attachment_size': size ?? bytes.length,
      'high_security': highSecurity,
    });
    await _media.uploadCipher(path, base64Decode(payload.ciphertextB64));
  }

  Future<Uint8List> openViewOnceImage({
    required NyvoxIdentity identity,
    required String decryptWithPublicKeyHex,
    required ChatMessage message,
    required bool destroy,
  }) =>
      openViewOnceAttachment(
        identity: identity,
        decryptWithPublicKeyHex: decryptWithPublicKeyHex,
        message: message,
        destroy: destroy,
      );

  Future<Uint8List> openViewOnceAttachment({
    required NyvoxIdentity identity,
    required String decryptWithPublicKeyHex,
    required ChatMessage message,
    required bool destroy,
  }) async {
    final path = message.attachmentPath!;
    final cipherBytes = await _media.downloadCipher(path);
    final plain = await _crypto.decryptBytes(
      myKeyPair: identity.keyPair,
      senderPublicKeyHex: decryptWithPublicKeyHex,
      ciphertextB64: base64Encode(cipherBytes),
      nonceB64: message.attachmentNonce!,
    );
    if (destroy) {
      try {
        await _client.from('messages').delete().eq('id', message.id);
      } finally {
        try {
          await _media.delete(path);
        } catch (_) {}
      }
    }
    return plain;
  }

  Future<void> markRead(String messageId) async {
    await _client
        .from('messages')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', messageId)
        .isFilter('read_at', null);
  }

  Future<void> markConversationRead(
      String conversationId, String myAccountId) async {
    await _client
        .from('messages')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('conversation_id', conversationId)
        .neq('sender_account_id', myAccountId)
        .isFilter('read_at', null);
  }

  Future<void> deleteMessage(String messageId) async {
    await _client.from('messages').delete().eq('id', messageId);
  }

  /// Permanently removes secure incoming messages when the recipient leaves
  /// the chat. Ciphertext attachments are removed from Storage as well.
  Future<void> purgeIncomingHighSecurity(
      String conversationId, String myAccountId) async {
    final rows = await _client
        .from('messages')
        .select('id, attachment_path')
        .eq('conversation_id', conversationId)
        .eq('high_security', true)
        .neq('sender_account_id', myAccountId);

    final items = (rows as List).cast<Map<String, dynamic>>();
    if (items.isEmpty) return;

    await _client
        .from('messages')
        .delete()
        .eq('conversation_id', conversationId)
        .eq('high_security', true)
        .neq('sender_account_id', myAccountId);

    for (final item in items) {
      final path = item['attachment_path'] as String?;
      if (path == null) continue;
      try {
        await _media.delete(path);
      } catch (_) {}
    }
  }

  Future<void> purgeExpired() async {
    await _client
        .from('messages')
        .delete()
        .lt('expires_at', DateTime.now().toUtc().toIso8601String());
  }
}
