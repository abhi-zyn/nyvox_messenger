import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/crypto_service.dart';

final cryptoServiceProvider = Provider<CryptoService>((ref) => CryptoService());

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final chatServiceProvider =
    Provider<ChatService>((ref) => ChatService(ref.watch(cryptoServiceProvider)));

/// The current device session (identity). Null → show onboarding.
/// Call `ref.invalidate(appSessionProvider)` after create/restore/wipe.
final appSessionProvider = FutureProvider<AppSession?>((ref) async {
  return ref.watch(authServiceProvider).loadSavedSession();
});

/// Conversations for the signed-in identity.
final conversationsProvider = FutureProvider<List<ConversationSummary>>((ref) async {
  final session = await ref.watch(appSessionProvider.future);
  if (session == null) return const [];
  return ref.watch(chatServiceProvider).listConversations(session.accountId);
});

/// Decrypted live messages for one open conversation.
final messagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, ({String conversationId, Profile peer})>(
  (ref, args) async* {
    final session = await ref.watch(appSessionProvider.future);
    if (session == null) {
      yield const <ChatMessage>[];
      return;
    }
    final keys = <String, String>{
      session.accountId: session.identity.publicKeyHex,
      args.peer.accountId: args.peer.publicKey,
    };
    yield* ref.watch(chatServiceProvider).watchMessages(
          conversationId: args.conversationId,
          myAccountId: session.accountId,
          identity: session.identity,
          publicKeysByAccount: keys,
        );
  },
);

/// Raw stream of every message visible to me (RLS-scoped) — used for local
/// notifications on the home screen.
final allMessagesProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final session = ref.watch(appSessionProvider).value;
  if (session == null) return const Stream.empty();
  return ref.watch(chatServiceProvider).watchAllMessagesRaw();
});
