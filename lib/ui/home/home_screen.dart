import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../models/models.dart';
import '../../state/providers.dart';
import '../chat/chat_screen.dart';
import '../contacts/add_contact_screen.dart';
import '../settings/settings_screen.dart';
import '../theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: NyvoxTheme.surfaceRaised,
        child: Text(summary.avatarEmoji, style: const TextStyle(fontSize: 24)),
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
      trailing: last == null
          ? null
          : Text(
              timeago.format(last.createdAt, clock: DateTime.now()),
              style: const TextStyle(color: NyvoxTheme.textSecondary, fontSize: 12),
            ),
      onTap: () {
        final peer = summary.peer;
        if (peer == null) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(conversationId: summary.id, peer: peer),
          ),
        );
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
