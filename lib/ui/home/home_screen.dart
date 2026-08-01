import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/app_session.dart';
import '../../state/providers.dart';
import '../chat/chat_screen.dart';
import '../settings/settings_screen.dart';
import '../theme.dart';
import 'add_contact_screen.dart';

/// Home: conversation list (DMs + groups) with unread badges,
/// privacy-safe notifications, and invite deep-link handling.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.session});

  final AppSession session;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _initialized = false;
  AppLinks? _appLinks;
  StreamSubscription<Uri>? _linkSub;
  final Set<String> _seenMessageIds = {};
  final Map<String, DateTime> _previewTimes = {};
  String? _activeConversationId;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  void _initDeepLinks() {
    _appLinks = AppLinks();
    _appLinks!.getInitialLink().then((uri) {
      if (uri != null) _handleLink(uri);
    });
    _linkSub = _appLinks!.uriLinkStream.listen(_handleLink);
  }

  Future<void> _handleLink(Uri uri) async {
    if (uri.scheme != 'nyvox' || uri.host != 'u') return;
    final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    if (!id.startsWith('vc')) return;
    await _openDmWithAccountId(id);
  }

  Future<void> _openDmWithAccountId(String accountId) async {
    final chat = ref.read(chatServiceProvider);
    final peer = await chat.lookupProfile(accountId);
    if (peer == null || !mounted) return;
    final convoId = await chat.getOrCreateDm(
        widget.session.profile.accountId, peer.accountId);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        conversationId: convoId,
        title: peer.displayName,
        peer: peer,
      ),
    ));
    ref.invalidate(conversationsProvider);
  }

  Future<void> _openNewChat() async {
    final result = await Navigator.of(context)
        .push<({String conversationId, Profile peer})?>(
      MaterialPageRoute(builder: (_) => const AddContactScreen()),
    );
    if (result == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        conversationId: result.conversationId,
        title: result.peer.displayName,
        peer: result.peer,
      ),
    ));
    ref.invalidate(conversationsProvider);
  }

  String _extractId(String input) {
    if (input.startsWith('nyvox://u/')) {
      return input.substring('nyvox://u/'.length).split('?').first;
    }
    final idx = input.indexOf('/u/');
    if (idx != -1) return input.substring(idx + 3).split('?').first;
    return input;
  }

  Future<void> _openNewGroup() async {
    final nameController = TextEditingController();
    final membersController = TextEditingController();
    final created = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              maxLength: 40,
              decoration: const InputDecoration(hintText: 'Group name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: membersController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Member Account IDs or invite links,\none per line',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final title = nameController.text.trim();
              if (title.isEmpty) return;
              final ids = membersController.text
                  .split(RegExp(r'[\s,]+'))
                  .map(_extractId)
                  .where((s) => s.startsWith('vc'))
                  .toSet()
                  .toList();
              final chat = ref.read(chatServiceProvider);
              final members = <Profile>[];
              for (final id in ids) {
                final p = await chat.lookupProfile(id);
                if (p != null) members.add(p);
              }
              final groupId = await chat.createGroupConversation(
                title: title,
                members: members,
                session: widget.session,
              );
              if (ctx.mounted) Navigator.pop(ctx, groupId);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (created == null || !mounted) return;
    ref.invalidate(conversationsProvider);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        conversationId: created,
        title: nameController.text.trim(),
        isGroup: true,
      ),
    ));
  }

  void _openFab() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add, color: NyvoxTheme.accent),
              title: const Text('New chat'),
              onTap: () {
                Navigator.pop(ctx);
                _openNewChat();
              },
            ),
            ListTile(
              leading: const Icon(Icons.groups, color: NyvoxTheme.accent),
              title: const Text('New group'),
              onTap: () {
                Navigator.pop(ctx);
                _openNewGroup();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<Profile?> _resolvePeer(String conversationId) async {
    final members = await ref
        .read(chatServiceProvider)
        .listMembersWithProfiles(conversationId);
    final myId = widget.session.profile.accountId;
    for (final p in members) {
      if (p.accountId != myId) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationsProvider);

    // Privacy-safe local notifications for incoming messages.
    ref.listen(allMessagesProvider, (prev, next) {
      next.whenData((items) {
        if (!_initialized) {
          _seenMessageIds.addAll(items.map((m) => m.id));
          for (final m in items) {
            _previewTimes[m.conversationId] = m.createdAt;
          }
          _initialized = true;
          return;
        }
        final convos = ref.read(conversationsProvider).value ?? [];
        for (final m in items) {
          _previewTimes[m.conversationId] = m.createdAt;
          if (_seenMessageIds.contains(m.id)) continue;
          _seenMessageIds.add(m.id);
          if (m.senderAccountId == widget.session.profile.accountId) continue;
          if (m.conversationId == _activeConversationId) continue;
          final title = convos
              .where((c) => c.id == m.conversationId)
              .map((c) => c.title)
              .firstOrNull;
          ref.read(notificationServiceProvider).showEncryptedMessage(
              conversationTitle: title ?? 'Nyvox');
        }
        ref.invalidate(conversationsProvider);
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nyvox',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SettingsScreen(session: widget.session),
            )),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openFab,
        child: const Icon(Icons.add_comment, color: Colors.black),
      ),
      body: conversations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🕶️', style: TextStyle(fontSize: 64)),
                  const SizedBox(height: 16),
                  const Text(
                    'No conversations yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Share your invite link or QR from Settings,\nor tap + to start a chat or group.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: NyvoxTheme.textSecondary),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(conversationsProvider),
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final c = items[i];
                final time = c.lastMessageAt ?? _previewTimes[c.id];
                return _ConversationTile(
                  summary: c,
                  previewTime: time,
                  onTap: () async {
                    _activeConversationId = c.id;
                    if (c.isGroup) {
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          conversationId: c.id,
                          title: c.title,
                          isGroup: true,
                        ),
                      ));
                    } else {
                      final peer = await _resolvePeer(c.id);
                      if (!mounted || peer == null) return;
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          conversationId: c.id,
                          title: c.title,
                          peer: peer,
                        ),
                      ));
                    }
                    _activeConversationId = null;
                    ref.invalidate(conversationsProvider);
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.summary,
    required this.onTap,
    this.previewTime,
  });

  final ConversationSummary summary;
  final VoidCallback onTap;
  final DateTime? previewTime;

  String _formatTime(DateTime? t) {
    if (t == null) return '';
    final local = t.toLocal();
    final now = DateTime.now();
    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (sameDay) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.day}/${local.month}';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: summary.isGroup
          ? CircleAvatar(
              radius: 24,
              backgroundColor: NyvoxTheme.accent.withValues(alpha: 0.15),
              child: const Icon(Icons.groups, color: NyvoxTheme.accent),
            )
          : UserAvatar(
              avatarUrl: null, fallbackText: summary.title, radius: 24),
      title: Text(summary.title),
      subtitle: Text(
        summary.isGroup ? 'Group chat' : 'Tap to chat',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: NyvoxTheme.textSecondary, fontSize: 13),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (previewTime != null)
            Text(
              _formatTime(previewTime),
              style: const TextStyle(
                  color: NyvoxTheme.textSecondary, fontSize: 12),
            ),
          const SizedBox(height: 4),
          if (summary.unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: NyvoxTheme.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${summary.unreadCount}',
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}
