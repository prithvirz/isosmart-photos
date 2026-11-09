import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/memory.model.dart';
import 'package:immich_mobile/presentation/pages/memory.page.dart';
import 'package:immich_mobile/presentation/widgets/images/thumbnail.widget.dart';
import 'package:immich_mobile/providers/haptic_feedback.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:path_provider/path_provider.dart';

final _storyPrefix = RegExp(r'^\u2728\s*');

String _storyKey(RemoteAlbum a) => '${a.id}@${a.updatedAt.millisecondsSinceEpoch}';

/// Stories already opened on this phone (kept in a small file).
final seenStoriesProvider = StateProvider<Set<String>>((ref) => <String>{});

Future<File> _seenFile() async => File('${(await getApplicationSupportDirectory()).path}/seen_stories.json');

/// Story albums made nightly by the home server (names start with the sparkle), minus the ones already watched.
final storyAlbumsProvider = Provider<List<RemoteAlbum>>((ref) {
  final seen = ref.watch(seenStoriesProvider);
  return ref
      .watch(remoteAlbumProvider)
      .albums
      .where((a) => _storyPrefix.hasMatch(a.name) && a.assetCount > 0 && !seen.contains(_storyKey(a)))
      .toList();
});

class StoriesRow extends ConsumerStatefulWidget {
  const StoriesRow({super.key});

  @override
  ConsumerState<StoriesRow> createState() => _StoriesRowState();
}

class _StoriesRowState extends ConsumerState<StoriesRow> {
  @override
  void initState() {
    super.initState();
    // Load albums on the timeline itself, not only after the Albums tab is opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(remoteAlbumProvider.notifier).refresh());
      unawaited(_loadSeen());
    });
  }

  Future<void> _loadSeen() async {
    try {
      final f = await _seenFile();
      if (!f.existsSync()) return;
      final saved = (jsonDecode(f.readAsStringSync()) as List).cast<String>();
      if (mounted) ref.read(seenStoriesProvider.notifier).state = {...ref.read(seenStoriesProvider), ...saved};
    } catch (_) {}
  }

  Future<void> _markSeen(RemoteAlbum album) async {
    final next = {...ref.read(seenStoriesProvider), _storyKey(album)};
    ref.read(seenStoriesProvider.notifier).state = next;
    try {
      // keep the last 200 only
      final list = next.toList();
      (await _seenFile()).writeAsStringSync(jsonEncode(list.length > 200 ? list.sublist(list.length - 200) : list));
    } catch (_) {}
  }

  Future<void> _open(RemoteAlbum album) async {
    ref.read(hapticFeedbackProvider.notifier).heavyImpact();
    final assets = await ref.read(remoteAlbumProvider.notifier).getAssets(album.id);
    if (!mounted) return;
    if (assets.isEmpty) {
      unawaited(context.router.push(RemoteAlbumRoute(album: album)));
      return;
    }
    final memory = Memory(
      id: album.id,
      createdAt: album.createdAt,
      updatedAt: album.updatedAt,
      ownerId: album.ownerId,
      type: MemoryTypeEnum.onThisDay,
      data: MemoryData(year: album.createdAt.year, personName: album.name.replaceFirst(_storyPrefix, '')),
      isSaved: true,
      memoryAt: album.createdAt,
      assets: assets,
    );
    MemoryPage.setMemory(ref, memory);
    unawaited(_markSeen(album));
    unawaited(context.pushRoute(MemoryRoute(memories: [memory], memoryIndex: 0)));
  }

  @override
  Widget build(BuildContext context) {
    final albums = ref.watch(storyAlbumsProvider);
    if (albums.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 190,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        itemCount: albums.length,
        itemBuilder: (context, i) {
          final album = albums[i];
          final parts = album.name.replaceFirst(_storyPrefix, '').split(' \u00b7 ');
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => unawaited(_open(album)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 122,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      album.thumbnailAssetId != null
                          ? Thumbnail.remote(remoteId: album.thumbnailAssetId!, thumbhash: '', fit: BoxFit.cover)
                          : Container(color: Colors.grey[800]),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.transparent, Color(0xCC000000)],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 10,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              parts.first,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, height: 1.15),
                            ),
                            if (parts.length > 1)
                              Text(parts[1], maxLines: 1, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
