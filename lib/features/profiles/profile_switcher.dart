import 'package:flutter/material.dart';
import 'package:personal_journal_app/features/profiles/profile_controller.dart';

class ProfileSwitcher extends StatelessWidget {
  const ProfileSwitcher({required this.controller, super.key});

  final ProfileController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final active = controller.active;
        if (controller.loading && active == null) {
          return const SizedBox(
            height: 48,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (active == null) return const SizedBox.shrink();
        return MenuAnchor(
          menuChildren: <Widget>[
            ...controller.profiles.map(
              (profile) => MenuItemButton(
                onPressed: controller.loading || profile.id == active.id
                    ? null
                    : () => _select(context, profile.id),
                child: Text(profile.name),
              ),
            ),
            const Divider(),
            MenuItemButton(
              onPressed: controller.loading ? null : () => _create(context),
              child: const Text('创建新用户'),
            ),
          ],
          builder: (context, menuController, _) => TextButton.icon(
            onPressed: controller.loading ? null : menuController.open,
            icon: const Icon(Icons.account_circle_outlined),
            label: Text(active.name),
          ),
        );
      },
    );
  }

  Future<void> _select(BuildContext context, String id) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.select(id);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('操作失败，请稍后重试')));
    }
  }

  Future<void> _create(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final textController = TextEditingController();
        return AlertDialog(
          title: const Text('创建新用户'),
          content: TextField(
            controller: textController,
            autofocus: true,
            decoration: const InputDecoration(labelText: '用户名称'),
            onSubmitted: (value) => Navigator.pop(dialogContext, value),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, textController.text),
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await controller.createAndSelect(name);
    } catch (_) {
      if (context.mounted) _showError(context);
    }
  }

  void _showError(BuildContext context) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('操作失败，请稍后重试')));
}
