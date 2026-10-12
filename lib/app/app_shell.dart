import 'package:flutter/material.dart';
import 'package:personal_journal_app/features/profiles/profile_controller.dart';
import 'package:personal_journal_app/features/profiles/profile_switcher.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.profileController, this.todayPage, super.key});
  final ProfileController profileController;
  final Widget? todayPage;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _selectedIndex = 0;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.profileController,
    builder: (context, _) => Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: <Widget>[
          widget.todayPage ?? _TodayPage(controller: widget.profileController),
          _CalendarPage(controller: widget.profileController),
          _ExportPage(profileId: widget.profileController.active?.id),
          const _PlaceholderPage(title: '设置'),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const <Widget>[
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: '今天',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '日历',
          ),
          NavigationDestination(
            icon: Icon(Icons.ios_share_outlined),
            selectedIcon: Icon(Icons.ios_share),
            label: '导出',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    ),
  );
}

class _TodayPage extends StatelessWidget {
  const _TodayPage({required this.controller});
  final ProfileController controller;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ProfileSwitcher(controller: controller),
          const SizedBox(height: 16),
          const Text('今天', style: TextStyle(fontSize: 24)),
          const SizedBox(height: 16),
          const Expanded(
            child: TextField(
              key: Key('today-draft-input'),
              maxLines: null,
              expands: true,
              decoration: InputDecoration(
                hintText: '记录此刻…',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CalendarPage extends StatelessWidget {
  const _CalendarPage({required this.controller});
  final ProfileController controller;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ProfileSwitcher(controller: controller),
          const SizedBox(height: 16),
          const Text('日历', style: TextStyle(fontSize: 24)),
          const SizedBox(height: 16),
          const Text('日历功能即将推出'),
        ],
      ),
    ),
  );
}

class _ExportPage extends StatelessWidget {
  const _ExportPage({required this.profileId});
  final String? profileId;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text('导出', style: TextStyle(fontSize: 24)),
        const SizedBox(height: 8),
        Text('当前用户范围', key: Key('export-profile-scope-${profileId ?? 'none'}')),
      ],
    ),
  );
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) =>
      Center(child: Text(title, style: const TextStyle(fontSize: 24)));
}
