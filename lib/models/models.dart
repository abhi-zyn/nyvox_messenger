class Profile {
  const Profile({
    required this.accountId,
    required this.displayName,
    required this.publicKey,
    required this.avatarEmoji,
    this.avatarUrl,
  });

  final String accountId;
  final String displayName;
  final String publicKey;
  final String avatarEmoji;
  final String? avatarUrl;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        accountId: json['account_id'] as String,
        displayName: json['display_name'] as String? ?? 'Anonymous',
        publicKey: json['public_key'] as String? ?? '',
        avatarEmoji: json['avatar_emoji'] as String? ?? '🕶️',
        avatarUrl: json['avatar_url'] as String?,
      );

  String get shortId =>
      accountId.length > 12 ? '${accountId.substring(0, 12)}…' : accountId;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderAccountId,
    required this.plaintext,
    required this.createdAt,
    required this.isMine,
    this.expiresAt,
    this.readAt,
    this.attachmentPath,
    this.attachmentNonce,
    this.attachmentType,
    this.attachmentName,
    this.attachmentSize,
    this.highSecurity = false,
  });

  final String id;
  final String conversationId;
  final String senderAccountId;

  /// Decrypted on-device. Null when decryption failed or this is an attachment.
  final String? plaintext;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? readAt;
  final bool isMine;

  /// Attachment stored in the private chat-media bucket. View-once items
  /// (images and files) are destroyed everywhere the moment the recipient
  /// opens them; voice notes persist like normal messages.
  final String? attachmentPath;
  final String? attachmentNonce;
  final String? attachmentType; // image | file | voice
  final String? attachmentName;
  final int? attachmentSize;
  final bool highSecurity;

  bool get hasAttachment => attachmentPath != null;

  /// Images sent before attachment_type existed have a null type.
  bool get isViewOnceImage =>
      hasAttachment && (attachmentType == null || attachmentType == 'image');
  bool get isFileAttachment => attachmentType == 'file';
  bool get isVoiceAttachment => attachmentType == 'voice';
  bool get isViewOnce => hasAttachment && !isVoiceAttachment;

  factory ChatMessage.fromJson(
    Map<String, dynamic> json, {
    required String myAccountId,
    String? plaintext,
  }) =>
      ChatMessage(
        id: json['id'] as String,
        conversationId: json['conversation_id'] as String,
        senderAccountId: json['sender_account_id'] as String,
        plaintext: plaintext,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.parse(json['expires_at'] as String).toLocal(),
        readAt: json['read_at'] == null
            ? null
            : DateTime.parse(json['read_at'] as String).toLocal(),
        isMine: json['sender_account_id'] == myAccountId,
        attachmentPath: json['attachment_path'] as String?,
        attachmentNonce: json['attachment_nonce'] as String?,
        attachmentType: json['attachment_type'] as String?,
        attachmentName: json['attachment_name'] as String?,
        attachmentSize: json['attachment_size'] as int?,
        highSecurity: json['high_security'] as bool? ?? false,
      );
}

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.isGroup,
    required this.createdAt,
    this.title,
    this.peer,
    this.lastMessage,
    this.unreadCount = 0,
  });

  final String id;
  final bool isGroup;
  final String? title;
  final Profile? peer;
  final ChatMessage? lastMessage;
  final DateTime createdAt;

  /// Incoming messages not yet marked read — shown as a badge, WhatsApp-style.
  final int unreadCount;

  String get displayName => peer?.displayName ?? title ?? 'Conversation';
  String get avatarEmoji => peer?.avatarEmoji ?? '💬';
}

/// A live conversation row — carries the synced disappearing-message timer,
/// so when one member changes it, everyone's app updates via realtime.
class ConversationInfo {
  const ConversationInfo({
    required this.id,
    required this.isGroup,
    this.title,
    this.disappearSeconds,
    this.highSecurity = false,
  });

  final String id;
  final bool isGroup;
  final String? title;
  final int? disappearSeconds;
  final bool highSecurity;

  factory ConversationInfo.fromJson(Map<String, dynamic> json) =>
      ConversationInfo(
        id: json['id'] as String,
        isGroup: json['is_group'] as bool? ?? false,
        title: json['title'] as String?,
        disappearSeconds: json['disappear_seconds'] as int?,
        highSecurity: json['high_security'] as bool? ?? false,
      );
}
