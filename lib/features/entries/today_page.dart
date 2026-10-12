import 'dart:async';
import 'dart:io';

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

typedef MediaFileResolver = Future<File> Function(String relativePath);

class TodayPage extends StatefulWidget {
  const TodayPage({
    required this.profileController,
    required this.draftController,
    required this.entryRepository,
    required this.mediaRepository,
    this.mediaPicker,
    this.mediaImporter,
    this.deletionService,
    this.mediaFileResolver,
    super.key,
  });

  final ProfileController profileController;
  final DraftController draftController;
  final EntryRepository entryRepository;
  final MediaRepository mediaRepository;
  final MediaPicker? mediaPicker;
  final MediaImporter? mediaImporter;
  final EntryDeletionService? deletionService;
  final MediaFileResolver? mediaFileResolver;

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
      final entries = await widget.entryRepository.listDay(
        profileId,
        DateTime.now(),
      );
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
        final entries = await widget.entryRepository.listDay(
          profileId,
          DateTime.now(),
        );
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

  Future<void> _pick(
    Future<List<PickedMedia>> Function(MediaPicker) select,
  ) async {
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

  Future<void> _reloadTimeline() async {
    final profileId = widget.profileController.active?.id;
    if (profileId == null) return;
    final entries = await widget.entryRepository.listDay(
      profileId,
      DateTime.now(),
    );
    if (!mounted || profileId != widget.profileController.active?.id) return;
    setState(() => _entries = entries);
  }

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
                children: _entries
                    .map(
                      (entry) => _TimelineCard(
                        entry: entry,
                        entryRepository: widget.entryRepository,
                        mediaRepository: widget.mediaRepository,
                        deletionService: widget.deletionService,
                        mediaFileResolver: widget.mediaFileResolver,
                        onChanged: _reloadTimeline,
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            TextField(
              key: const Key('today-draft-input'),
              controller: widget.draftController.textController,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '记录此刻…',
                border: OutlineInputBorder(),
              ),
            ),
            Row(
              children: <Widget>[
                if (widget.mediaPicker != null) ...<Widget>[
                  IconButton(
                    key: const Key('today-add-images'),
                    onPressed: _pickImages,
                    icon: const Icon(Icons.image_outlined),
                  ),
                  IconButton(
                    key: const Key('today-add-video'),
                    onPressed: _pickVideo,
                    icon: const Icon(Icons.videocam_outlined),
                  ),
                ],
                Expanded(
                  child: _MediaStrip(
                    media: _draftMedia,
                    mediaFileResolver: widget.mediaFileResolver,
                  ),
                ),
                FilledButton(
                  key: const Key('today-save'),
                  onPressed: _canSave && !_saving ? _publish : null,
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _TimelineCard extends StatefulWidget {
  const _TimelineCard({
    required this.entry,
    required this.entryRepository,
    required this.mediaRepository,
    required this.deletionService,
    required this.mediaFileResolver,
    required this.onChanged,
  });
  final JournalEntry entry;
  final EntryRepository entryRepository;
  final MediaRepository mediaRepository;
  final EntryDeletionService? deletionService;
  final MediaFileResolver? mediaFileResolver;
  final Future<void> Function() onChanged;

  @override
  State<_TimelineCard> createState() => _TimelineCardState();
}

class _TimelineCardState extends State<_TimelineCard> {
  late Future<List<MediaItem>> _media;

  @override
  void initState() {
    super.initState();
    _media = widget.mediaRepository.listForEntry(widget.entry.id);
  }

  @override
  void didUpdateWidget(covariant _TimelineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id ||
        oldWidget.mediaRepository != widget.mediaRepository) {
      _media = widget.mediaRepository.listForEntry(widget.entry.id);
    }
  }

  Future<void> _openEditor(BuildContext context) async {
    final deletionService = widget.deletionService;
    if (deletionService == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => EntryEditorPage(
          entry: widget.entry,
          entryRepository: widget.entryRepository,
          mediaRepository: widget.mediaRepository,
          deletionService: deletionService,
        ),
      ),
    );
    if (changed == true) await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => Card(
    key: Key('timeline-card-${widget.entry.id}'),
    child: InkWell(
      onTap: widget.deletionService == null ? null : () => _openEditor(context),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              TimeOfDay.fromDateTime(
                widget.entry.createdAt.add(
                  Duration(minutes: widget.entry.timezoneOffsetMinutes),
                ),
              ).format(context),
            ),
            if (widget.entry.text.isNotEmpty) Text(widget.entry.text),
            FutureBuilder<List<MediaItem>>(
              future: _media,
              builder: (context, snapshot) => _MediaStrip(
                media: snapshot.data ?? const <MediaItem>[],
                mediaFileResolver: widget.mediaFileResolver,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MediaStrip extends StatelessWidget {
  const _MediaStrip({required this.media, required this.mediaFileResolver});
  final List<MediaItem> media;
  final MediaFileResolver? mediaFileResolver;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: media
        .map(
          (item) => SizedBox.square(
            key: Key('media-preview-${item.id}'),
            dimension: 88,
            child: _MediaPreview(
              item: item,
              mediaFileResolver: mediaFileResolver,
            ),
          ),
        )
        .toList(growable: false),
  );
}

class _MediaPreview extends StatefulWidget {
  const _MediaPreview({required this.item, required this.mediaFileResolver});

  final MediaItem item;
  final MediaFileResolver? mediaFileResolver;

  @override
  State<_MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<_MediaPreview> {
  Future<File>? _file;

  String? get _previewPath => widget.item.type == MediaType.video
      ? widget.item.thumbnailPath
      : widget.item.relativePath;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _MediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPath = oldWidget.item.type == MediaType.video
        ? oldWidget.item.thumbnailPath
        : oldWidget.item.relativePath;
    if (oldPath != _previewPath ||
        oldWidget.mediaFileResolver != widget.mediaFileResolver) {
      _resolve();
    }
  }

  void _resolve() {
    final path = _previewPath;
    final resolver = widget.mediaFileResolver;
    _file = path == null || resolver == null ? null : resolver(path);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _file == null
        ? _fallback()
        : FutureBuilder<File>(
            future: _file,
            builder: (context, snapshot) {
              final file = snapshot.data;
              if (file == null) return _fallback();
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  file,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _fallback(),
                ),
              );
            },
          );
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        preview,
        if (widget.item.type == MediaType.video) ...<Widget>[
          const Center(
            child: Icon(Icons.play_circle_fill, color: Colors.white, size: 34),
          ),
          if (widget.item.durationMilliseconds != null)
            Positioned(
              right: 4,
              bottom: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    '${widget.item.durationMilliseconds! ~/ 1000}s',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _fallback() => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black12,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(
      widget.item.type == MediaType.image ? Icons.image : Icons.videocam,
      semanticLabel: widget.item.originalFilename,
    ),
  );
}
