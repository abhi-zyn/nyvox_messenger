import 'dart:convert';

/// Nyvox identity derived entirely from a BIP-39 mnemonic.
class IdentityKeys {
  IdentityKeys({
    required this.mnemonic,
    required this.privateKey,
    required this.publicKey,
  });

  final String mnemonic;
  final List<int> privateKey;
  final List<int> publicKey;

  String get accountId =>
      'vc${publicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

class Profile {
  Profile({
    required this.accountId,
    required this.displayName,
    required this.publicKey,
    this.avatarUrl,
  });

  factory Profile.fromRow(Map<String, dynamic> row) => Profile(
        accountId: row['account_id'] as String,
        displayName: row['display_name'] as String? ?? 'Anonymous',
        publicKey: List<int>.from(base64Decode(row['public_key'] as String)),
        avatarUrl: row['avatar_url'] as String?,
      );

  final String accountId;
  final String displayName;
  final List<int> publicKey;
  final String? avatarUrl;
}

class ConversationSummary {
  ConversationSummary({
    required this.id,
    required this.title,
    required this.isGroup,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  final String id;
  final String title;
  final bool isGroup;
  final DateTime? lastMessageAt;
  final int unreadCount;
}

/// A conversation row as seen by the client (carries the synced
/// disappearing-message timer).
class ConversationInfo {
  ConversationInfo({
    required this.id,
    required this.isGroup,
    this.title,
    this.disappearSeconds,
  });

  factory ConversationInfo.fromRow(Map<String, dynamic> row) =>
      ConversationInfo(
        id: row['id'] as String,
        isGroup: row['is_group'] as bool? ?? false,
        title: row['title'] as String?,
        disappearSeconds: row['disappear_seconds'] as int?,
      );

  final String id;
  final bool isGroup;
  final String? title;
  final int? disappearSeconds;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderAccountId,
    required this.ciphertext,
    required this.nonce,
    required this.createdAt,
    this.readAt,
    this.expiresAt,
    this.plaintext,
    this.attachmentPath,
    this.attachmentNonce,
    this.attachmentType,
    this.attachmentName,
    this.attachmentSize,
  });

  factory ChatMessage.fromRow(Map<String, dynamic> row) => ChatMessage(
        id: row['id'] as String,
        conversationId: row['conversation_id'] as String,
        senderAccountId: row['sender_account_id'] as String,
        ciphertext: row['ciphertext'] as String? ?? '',
        nonce: row['nonce'] as String? ?? '',
        createdAt: DateTime.parse(row['created_at'] as String),
        readAt: row['read_at'] == null
            ? null
            : DateTime.parse(row['read_at'] as String),
        expiresAt: row['expires_at'] == null
            ? null
            : DateTime.parse(row['expires_at'] as String),
        attachmentPath: row['attachment_path'] as String?,
        attachmentNonce: row['attachment_nonce'] as String?,
        attachmentType: row['attachment_type'] as String?,
        attachmentName: row['attachment_name'] as String?,
        attachmentSize: row['attachment_size'] as int?,
      );

  final String id;
  final String conversationId;
  final String senderAccountId;
  final String ciphertext;
  final String nonce;
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? expiresAt;
  String? plaintext;
  final String? attachmentPath;
  final String? attachmentNonce;
  final String? attachmentType; // image | file | voice
  final String? attachmentName;
  final int? attachmentSize;

  bool get hasAttachment => attachmentPath != null;

  /// Images sent before attachment_type existed have a null type.
  bool get isViewOnceImage =>
      hasAttachment && (attachmentType == null || attachmentType == 'image');
  bool get isFileAttachment => attachmentType == 'file';
  bool get isVoiceAttachment => attachmentType == 'voice';

  /// View-once items (images and files) are destroyed after being opened;
  /// voice notes persist like normal messages.
  bool get isViewOnce => hasAttachment && !isVoiceAttachment;

  bool get isExpired =>
      expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt!);
}
