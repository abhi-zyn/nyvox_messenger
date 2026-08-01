import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../theme.dart';

enum _Step { welcome, create, phrase, restore }

/// Session-style onboarding: no phone, no email — create an identity
/// (backed up by a 12-word recovery phrase) or restore an existing one.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _Step _step = _Step.welcome;
  final _nameController = TextEditingController();
  final _phraseController = TextEditingController();
  bool _busy = false;
  String? _createdMnemonic;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phraseController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session =
          await ref.read(authServiceProvider).createAccount(_nameController.text);
      if (!mounted) return;
      setState(() {
        _createdMnemonic = session.identity.mnemonic;
        _step = _Step.phrase;
      });
    } catch (e) {
      setState(() => _error = 'Could not create your account.\n$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).restoreAccount(_phraseController.text);
      _finish();
    } catch (e) {
      setState(() => _error = 'Could not restore. Check your 12 words.\n$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish() => ref.invalidate(appSessionProvider);

  @override
  Widget build(BuildContext context) {
    // Scrollable so the action button is ALWAYS reachable — on smaller
    // screens (or with the keyboard open) a fixed Column pushed the button
    // off-screen, making it seem unclickable.
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: switch (_step) {
            _Step.welcome => _welcome(),
            _Step.create => _createStep(),
            _Step.phrase => _phraseStep(),
            _Step.restore => _restoreStep(),
          },
        ),
      ),
    );
  }

  Widget _welcome() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 48),
        const Text('🕶️', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 16),
        const Text(
          'Send messages,\nnot metadata.',
          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1.1),
        ),
        const SizedBox(height: 24),
        const _FeatureRow(icon: Icons.key, text: 'No phone number or email — your Account ID is your identity'),
        const _FeatureRow(icon: Icons.lock, text: 'End-to-end encrypted on your device (X25519 + AES-GCM)'),
        const _FeatureRow(icon: Icons.timer, text: 'Disappearing messages, on by design'),
        const SizedBox(height: 40),
        FilledButton(
          onPressed: () => setState(() => _step = _Step.create),
          child: const Text('Create account'),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => setState(() => _step = _Step.restore),
            child: const Text('Restore from recovery phrase'),
          ),
        ),
      ],
    );
  }

  Widget _createStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _step = _Step.welcome),
        ),
        const SizedBox(height: 8),
        const Text('Choose a display name',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
          'It can be your real name, an alias, or anything. It is the only thing people see besides your Account ID.',
          style: TextStyle(color: NyvoxTheme.textSecondary),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _nameController,
          maxLength: 32,
          decoration: const InputDecoration(hintText: 'e.g. fox_42'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        ],
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _busy ? null : _create,
          child: _busy
              ? const SizedBox(
                  height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Continue'),
        ),
      ],
    );
  }

  Widget _phraseStep() {
    final words = (_createdMnemonic ?? '').split(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Save your recovery phrase',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
          'These 12 words are the ONLY way to recover your account. Write them down and keep them secret.',
          style: TextStyle(color: NyvoxTheme.textSecondary),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.6,
              children: [
                for (var i = 0; i < words.length; i++)
                  Text('${i + 1}. ${words[i]}',
                      style: const TextStyle(fontFamily: 'monospace')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy to clipboard'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _createdMnemonic ?? ''));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Recovery phrase copied')),
                );
              }
            },
          ),
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _finish,
          child: const Text("I've saved it — continue"),
        ),
      ],
    );
  }

  Widget _restoreStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _step = _Step.welcome),
        ),
        const SizedBox(height: 8),
        const Text('Restore your account',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
          'Enter the 12 words of your recovery phrase, separated by spaces.',
          style: TextStyle(color: NyvoxTheme.textSecondary),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _phraseController,
          maxLines: 4,
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'word1 word2 word3 …',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        ],
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _busy ? null : _restore,
          child: _busy
              ? const SizedBox(
                  height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Restore account'),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: NyvoxTheme.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(color: NyvoxTheme.textSecondary)),
          ),
        ],
      ),
    );
  }
}
