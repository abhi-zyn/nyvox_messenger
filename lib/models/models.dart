class Profile {
  const Profile({
    required this.accountId,
    required this.displayName,
    required this.publicKey,
    required this.avatarEmoji,
  });

  final String accountId;
  final String displayName;
  final String publicKey;
  final String avatarEmoji;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        accountId: json['account_id'] as String,
        displayName: json['display_name'] as String? ?? 'Anonymous',
        publicKey: json['public_key'] as String? ?? '',
        avatarEmoji: json['avatar_emoji'] as String? ?? '🕶️',
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
  });

  final String id;
  final String conversationId;
  final String senderAccountId;

  /// Decrypted on-device. Null when decryption failed (e.g. unknown sender key).
  final String? plaintext;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? readAt;
  final bool isMine;

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
