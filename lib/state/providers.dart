import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../services/auth_service.dart';
import '../services/avatar_service.dart';
import '../services/chat_service.dart';
import '../services/file_service.dart';
import '../services/notification_service.dart';
import '../services/profile_service.dart';
import '../services/supabase_client.dart';
import 'app_session.dart';

final authServiceProvider = Provider((ref) => AuthService());
final profileServiceProvider = Provider((ref) => ProfileService());
final chatServiceProvider = Provider((ref) => ChatService());
final fileServiceProvider = Provider((ref) => FileService());
final notificationServiceProvider = Provider((ref) => NotificationService());
final avatarServiceProvider = Provider((ref) => AvatarService());

final appSessionProvider = FutureProvider<AppSession?>((ref) async {
  final auth = ref.watch(authServiceProvider);
  return auth.loadSavedSession();
});

final conversationsProvider =
    StreamProvider<List<ConversationSummary>>((ref) async* {
  final session = await ref.watch(appSessionProvider.future);
  if (session == null) {
    yield const [];
    return;
  }
  final chat = ref.watch(chatServiceProvider);
  final myId = session.profile.accountId;
  await for (final rows in chat.watchConversationRows(myId)) {
    final result = <ConversationSummary>[];
    for (final row in rows) {
      final id = row['conversation_id'] as String;
      final summary = await chat.loadConversationSummary(id, myId);
      if (summary == null) continue;
      final unread = await chat.unreadCount(id, myId);
      result.add(ConversationSummary(
        id: summary.id,
        title: summary.title,
        isGroup: summary.isGroup,
        lastMessageAt: summary.lastMessageAt,
        unreadCount: unread,
      ));
    }
    result.sort((a, b) =>
        (b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(
                a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
    yield result;
  }
});

/// Latest message of every conversation (drives realtime previews,
/// unread badges and privacy-safe notifications).
final allMessagesProvider = StreamProvider<List<ChatMessage>>((ref) async* {
  final session = await ref.watch(appSessionProvider.future);
  if (session == null) {
    yield const [];
    return;
  }
  final stream = NyvoxSupabase.client
      .from('messages')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(500);
  await for (final rows in stream) {
    final latest = <ChatMessage>[];
    final seen = <String>{};
    for (final r in rows) {
      final cid = r['conversation_id'] as String;
      if (!seen.add(cid)) continue;
      latest.add(ChatMessage.fromRow(r));
    }
    yield latest;
  }
});

final messagesProvider = StreamProvider.family<List<ChatMessage>,
    ({String conversationId, Profile peer})>((ref, args) async* {
  final session = await ref.watch(appSessionProvider.future);
  if (session == null) {
    yield const [];
    return;
  }
  final chat = ref.watch(chatServiceProvider);
  yield* chat.watchMessages(
    conversationId: args.conversationId,
    peer: args.peer,
    session: session,
  );
});

/// Synced conversation state (disappearing timer, title…).
final conversationInfoProvider =
    StreamProvider.family<ConversationInfo, String>((ref, conversationId) {
  final chat = ref.watch(chatServiceProvider);
  return chat.watchConversation(conversationId);
});

/// Everything a group chat screen needs: the decrypted group key plus
/// member profiles (for sender names on bubbles).
class GroupContext {
  GroupContext({required this.keyBytes, required this.members});

  final List<int> keyBytes;
  final Map<String, Profile> members; // accountId -> profile
}

final groupContextProvider =
    FutureProvider.family<GroupContext, String>((ref, conversationId) async {
  final session = await ref.watch(appSessionProvider.future);
  if (session == null) throw StateError('No session');
  final chat = ref.watch(chatServiceProvider);
  final key = await chat.getGroupKey(conversationId, session);
  final members = await chat.listMembersWithProfiles(conversationId);
  return GroupContext(
    keyBytes: key,
    members: {for (final p in members) p.accountId: p},
  );
});

final groupMessagesProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, conversationId) async* {
  final ctx = await ref.watch(groupContextProvider(conversationId).future);
  final chat = ref.watch(chatServiceProvider);
  yield* chat.watchGroupMessages(
    conversationId: conversationId,
    groupKey: ctx.keyBytes,
  );
});
