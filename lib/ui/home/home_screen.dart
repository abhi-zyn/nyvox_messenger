import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../models/models.dart';
import '../../services/notification_service.dart';
import '../../state/providers.dart';
import '../chat/chat_screen.dart';
import '../contacts/add_contact_screen.dart';
import '../settings/settings_screen.dart';
import '../theme.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Ids we've already seen — prevents re-notifying on every stream refresh.
  final Set<String> _seenMessageIds = <String>{};

  /// Only notify for messages that arrive after the app opened.
  final DateTime _listenerStart = DateTime.now();

  void _listenForIncoming() {
    ref.listen(allMessagesProvider, (previous, next) {
      final rows = next.value;
      final session = ref.read(appSessionProvider).value;
      if (rows == null || session == null) return;
      for (final row in rows) {
        final id = row['id'] as String;
        if (!_seenMessageIds.add(id)) continue;
        if (row['sender_account_id'] == session.accountId) continue;
        final createdAt = DateTime.parse(row['created_at'] as String);
        if (createdAt.isBefore(_listenerStart)) continue;
        notificationService.showMessageNotification();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _listenForIncoming();
    final conversations = ref.watch(conversationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nyvox'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: NyvoxTheme.accent,
        foregroundColor: Colors.black,
        child: const Icon(Icons.edit_outlined),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddContactScreen()),
        ),
      ),
      body: conversations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load chats\n$e')),
        data: (items) => items.isEmpty
            ? const _EmptyState()
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(conversationsProvider),
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 84),
                  itemBuilder: (context, i) =>
                      _ConversationTile(summary: items[i]),
                ),
              ),
      ),
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.summary});

  final ConversationSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = summary.lastMessage;
    final avatarUrl = summary.peer?.avatarUrl;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: NyvoxTheme.surfaceRaised,
        backgroundImage:
            avatarUrl != null ? NetworkImage(avatarUrl) : null,
        child: avatarUrl == null
            ? Text(summary.avatarEmoji, style: const TextStyle(fontSize: 24))
            : null,
      ),
      title: Text(
        summary.displayName,
        style: const TextStyle(fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        last == null ? 'Say hello 👋' : (last.plaintext ?? '🔒 encrypted message'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: NyvoxTheme.textSecondary),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (last != null)
            Text(
              timeago.format(last.createdAt, clock: DateTime.now()),
              style: const TextStyle(color: NyvoxTheme.textSecondary, fontSize: 12),
            ),
          if (summary.unreadCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: NyvoxTheme.accent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${summary.unreadCount}',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
      onTap: () async {
        final peer = summary.peer;
        if (peer == null) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(conversationId: summary.id, peer: peer),
          ),
        );
        // Refresh so the unread badge clears and the last message updates.
        ref.invalidate(conversationsProvider);
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🕊️', style: TextStyle(fontSize: 48)),
            SizedBox(height: 16),
            Text(
              'No conversations yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'Tap the pencil to start a chat with an Account ID or QR code.',
              textAlign: TextAlign.center,
              style: TextStyle(color: NyvoxTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
