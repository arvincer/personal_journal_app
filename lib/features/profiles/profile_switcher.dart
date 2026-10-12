import 'package:flutter/material.dart';
import 'package:personal_journal_app/features/profiles/profile_controller.dart';

class ProfileSwitcher extends StatefulWidget {
  const ProfileSwitcher({required this.controller, super.key});
  final ProfileController controller;
  @override
  State<ProfileSwitcher> createState() => _ProfileSwitcherState();
}

class _ProfileSwitcherState extends State<ProfileSwitcher> {
  bool _busy = false;
  ProfileController get controller => widget.controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final active = controller.active;
      if (controller.loading && active == null) {
        return const SizedBox(
          height: 48,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (active == null) {
        return const SizedBox.shrink();
      }
      final disabled = _busy || controller.loading;
      return MenuAnchor(
        menuChildren: <Widget>[
          ...controller.profiles.map(
            (profile) => MenuItemButton(
              onPressed: disabled || profile.id == active.id
                  ? null
                  : () => _select(context, profile.id),
              child: Text(profile.name),
            ),
          ),
          const Divider(),
          MenuItemButton(
            onPressed: disabled ? null : () => _create(context),
            child: const Text('创建新用户'),
          ),
        ],
        builder: (context, menuController, _) => TextButton.icon(
          onPressed: disabled ? null : menuController.open,
          icon: const Icon(Icons.account_circle_outlined),
          label: Text(active.name),
        ),
      );
    },
  );

  Future<void> _select(BuildContext context, String id) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await controller.select(id);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('操作失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create(BuildContext context) async {
    if (_busy) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateProfileDialog(),
    );
    if (!context.mounted || name == null || name.trim().isEmpty || _busy) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await controller.createAndSelect(name);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('操作失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void showError(BuildContext context) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('操作失败，请稍后重试')));
}

class _CreateProfileDialog extends StatefulWidget {
  const _CreateProfileDialog();
  @override
  State<_CreateProfileDialog> createState() => _CreateProfileDialogState();
}

class _CreateProfileDialogState extends State<_CreateProfileDialog> {
  final _textController = TextEditingController();
  bool _submitting = false;
  void _submit() {
    if (_submitting) return;
    setState(() => _submitting = true);
    Navigator.pop(context, _textController.text);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('创建新用户'),
    content: TextField(
      controller: _textController,
      autofocus: true,
      decoration: const InputDecoration(labelText: '用户名称'),
      onSubmitted: (_) => _submit(),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: _submitting ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _submitting ? null : _submit,
        child: const Text('创建'),
      ),
    ],
  );
}
