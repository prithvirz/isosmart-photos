import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/widgets/images/thumbnail.widget.dart';
import 'package:immich_mobile/providers/haptic_feedback.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/routing/router.dart';

class StoriesRow extends ConsumerWidget {
  const StoriesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumState = ref.watch(remoteAlbumProvider);
    // Find albums built by immich-stories (names starting with ✨)
    final storyAlbums = albumState.albums.where((a) => a.name.startsWith('✨') && a.assetCount > 0).toList();

    if (storyAlbums.isEmpty) {
      return const SizedBox.shrink();
    }

    void openStory(RemoteAlbum album) {
      ref.read(hapticFeedbackProvider.notifier).heavyImpact();
      unawaited(context.router.push(RemoteAlbumRoute(album: album)));
    }

    return Container(
      height: 140,
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Text('✨', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(
                  'Stories',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.primaryColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: storyAlbums.length,
              itemBuilder: (context, index) {
                final album = storyAlbums[index];
                // Clean display name: remove '✨ ' prefix
                final cleanTitle = album.name.replaceFirst(RegExp(r'^✨\s*'), '');

                return Container(
                  width: 95,
                  margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => openStory(album),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Card circular/rounded thumbnail
                        Container(
                          width: 76,
                          height: 76,
                          padding: const EdgeInsets.all(2.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: context.primaryColor, width: 2),
                          ),
                          child: ClipOval(
                            child: album.thumbnailAssetId != null
                                ? Thumbnail.remote(
                                    remoteId: album.thumbnailAssetId!,
                                    thumbhash: '',
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: Colors.grey[800],
                                    child: const Icon(Icons.photo, color: Colors.white70, size: 28),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Album title
                        Text(
                          cleanTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
