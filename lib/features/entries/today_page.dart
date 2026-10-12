import 'dart:async';

import 'package:flutter/material.dart';
import 'package:personal_journal_app/core/platform/media_picker.dart';
import 'package:personal_journal_app/features/entries/draft_controller.dart';
import 'package:personal_journal_app/features/entries/entry.dart';
import 'package:personal_journal_app/features/entries/entry_editor_page.dart';
import 'package:personal_journal_app/features/entries/entry_repository.dart';
import 'package:personal_journal_app/features/entries/media_import_service.dart';
import 'package:personal_journal_app/features/entries/media_item.dart';
import 'package:personal_journal_app/features/entries/media_repository.dart';
import 'package:personal_journal_app/features/profiles/profile_controller.dart';
import 'package:personal_journal_app/features/profiles/profile_switcher.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({
    required this.profileController,
    required this.draftController,
    required this.entryRepository,
    required this.mediaRepository,
    this.mediaPicker,
    this.mediaImporter,
    this.deletionService,
    super.key,
  });

  final ProfileController profileController;
  final DraftController draftController;
  final EntryRepository entryRepository;
  final MediaRepository mediaRepository;
  final MediaPicker? mediaPicker;
  final MediaImporter? mediaImporter;
  final EntryDeletionService? deletionService;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  List<JournalEntry> _entries = const <JournalEntry>[];
  List<MediaItem> _draftMedia = const <MediaItem>[];
  String? _loadedProfileId;
  int _generation = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    widget.profileController.addListener(_syncProfile);
    widget.draftController.addListener(_refresh);
    widget.draftController.textController.addListener(_refresh);
    _syncProfile();
  }

  @override
  void dispose() {
    widget.profileController.removeListener(_syncProfile);
    widget.draftController.removeListener(_refresh);
    widget.draftController.textController.removeListener(_refresh);
    super.dispose();
  }

  void _syncProfile() {
    final id = widget.profileController.active?.id;
    if (id == null || id == _loadedProfileId) return;
    final generation = ++_generation;
    _loadedProfileId = id;
    unawaited(_load(id, generation));
  }

  Future<void> _load(String profileId, int generation) async {
    try {
      if (widget.draftController.profileId == null) {
        await widget.draftController.initialize(profileId);
      } else if (widget.draftController.profileId != profileId) {
        await widget.draftController.switchProfile(profileId);
      }
      final entries = await widget.entryRepository.listDay(profileId, DateTime.now());
      final draft = await widget.entryRepository.getDraft(profileId);
      final draftMedia = draft == null
          ? const <MediaItem>[]
          : await widget.mediaRepository.listForEntry(draft.id);
      if (!mounted || generation != _generation) return;
      setState(() {
        _entries = entries;
        _draftMedia = draftMedia;
      });
    } catch (_) {
      // The app can close its database while this retained IndexedStack page
      // is resolving its initial profile; there is no UI to update then.
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _publish() async {
    if (_saving || !_canSave) return;
    setState(() => _saving = true);
    try {
      await widget.draftController.publish();
      final profileId = widget.profileController.active?.id;
      if (profileId != null) {
        final entries = await widget.entryRepository.listDay(profileId, DateTime.now());
        if (mounted && profileId == widget.profileController.active?.id) {
          setState(() {
            _entries = entries;
            _draftMedia = const <MediaItem>[];
          });
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImages() => _pick((picker) => picker.pickImages());
  Future<void> _pickVideo() => _pick((picker) async {
        final selected = await picker.pickVideo();
        return selected == null ? const <PickedMedia>[] : <PickedMedia>[selected];
      });

  Future<void> _pick(Future<List<PickedMedia>> Function(MediaPicker) select) async {
    final picker = widget.mediaPicker;
    final importer = widget.mediaImporter;
    if (picker == null || importer == null) return;
    final selected = await select(picker);
    if (selected.isEmpty) return;
    final draft = await widget.draftController.ensureDraft();
    for (final item in selected) {
      await importer.importMedia(entryId: draft.id, media: item);
    }
    final media = await widget.mediaRepository.listForEntry(draft.id);
    if (mounted) setState(() => _draftMedia = media);
  }

  bool get _canSave =>
      widget.draftController.textController.text.trim().isNotEmpty ||
      _draftMedia.isNotEmpty;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ProfileSwitcher(controller: widget.profileController),
                const SizedBox(height: 12),
                const Text('今天', style: TextStyle(fontSize: 24)),
                Expanded(
                  child: ListView(
                    children: _entries.map((entry) => _TimelineCard(
                      entry: entry,
                      entryRepository: widget.entryRepository,
                      mediaRepository: widget.mediaRepository,
                      deletionService: widget.deletionService,
                    )).toList(growable: false),
                  ),
                ),
                TextField(
                  key: const Key('today-draft-input'),
                  controller: widget.draftController.textController,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(hintText: '记录此刻…', border: OutlineInputBorder()),
                ),
                Row(
                  children: <Widget>[
                    if (widget.mediaPicker != null) ...<Widget>[
                      IconButton(key: const Key('today-add-images'), onPressed: _pickImages, icon: const Icon(Icons.image_outlined)),
                      IconButton(key: const Key('today-add-video'), onPressed: _pickVideo, icon: const Icon(Icons.videocam_outlined)),
                    ],
                    Expanded(child: _MediaStrip(media: _draftMedia)),
                    FilledButton(key: const Key('today-save'), onPressed: _canSave && !_saving ? _publish : null, child: const Text('保存')),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.entry, required this.entryRepository, required this.mediaRepository, required this.deletionService});
  final JournalEntry entry;
  final EntryRepository entryRepository;
  final MediaRepository mediaRepository;
  final EntryDeletionService? deletionService;
  @override
  Widget build(BuildContext context) => Card(
    key: Key('timeline-card-${entry.id}'),
    child: InkWell(
      onTap: deletionService == null ? null : () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => EntryEditorPage(entry: entry, entryRepository: entryRepository, mediaRepository: mediaRepository, deletionService: deletionService!))),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(TimeOfDay.fromDateTime(entry.createdAt.add(Duration(minutes: entry.timezoneOffsetMinutes))).format(context)),
          if (entry.text.isNotEmpty) Text(entry.text),
          FutureBuilder<List<MediaItem>>(
            future: mediaRepository.listForEntry(entry.id),
            builder: (context, snapshot) => _MediaStrip(media: snapshot.data ?? const <MediaItem>[]),
          ),
        ]),
      ),
    ),
  );
}

class _MediaStrip extends StatelessWidget {
  const _MediaStrip({required this.media});
  final List<MediaItem> media;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    children: media.map((item) => Chip(
      key: Key('media-preview-${item.id}'),
      avatar: Icon(item.type == MediaType.image ? Icons.image : Icons.videocam),
      label: Text(item.type == MediaType.video && item.durationMilliseconds != null ? '${item.durationMilliseconds! ~/ 1000}s' : item.originalFilename),
    )).toList(growable: false),
  );
}
