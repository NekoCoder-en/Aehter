import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../theme/app_colors.dart';
import '../services/audio_manager.dart';
import '../utils/image_utils.dart';
import 'full_player.dart';

import '../services/playlist_manager.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  Color _bgColor = const Color(0xFF2C2C2C);
  int? _lastSongId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateColor();
  }

  Future<void> _updateColor() async {
    final audioManager = context.read<AudioManager>();
    final song = audioManager.currentSong;
    if (song != null && song.id != _lastSongId) {
      _lastSongId = song.id;
      final metadata = audioManager.simulatedMetadata[song.data];
      final artworkUrl = metadata != null ? metadata['artworkUrl'] : null;
      
      final color = await ImageUtils.getDominantColor(song.id, imageUrl: artworkUrl);
      if (mounted) {
        setState(() => _bgColor = color);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioManager = context.watch<AudioManager>();
    final song = audioManager.currentSong;

    if (song == null) return const SizedBox.shrink();

    // Call update color in case the song changed
    if (song.id != _lastSongId) {
      _updateColor();
    }

    final metadata = audioManager.simulatedMetadata[song.data];
    final artist = metadata != null ? metadata['artist'] : (song.artist ?? "Desconocido");
    final title = metadata != null ? metadata['title'] : song.title;
    final artworkUrl = metadata != null ? metadata['artworkUrl'] : null;

    Widget artworkWidget;
    if (artworkUrl != null) {
      artworkWidget = artworkUrl.startsWith('file://') 
          ? Image.file(File(artworkUrl.replaceFirst('file://', '')), width: 48, height: 48, fit: BoxFit.cover)
          : Image.network(
              artworkUrl,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => QueryArtworkWidget(
                id: song.id,
                type: ArtworkType.AUDIO,
                artworkWidth: 48,
                artworkHeight: 48,
                size: 200,
                nullArtworkWidget: Container(
                  width: 48,
                  height: 48,
                  color: Colors.grey.shade800,
                  child: const Center(
                    child: FaIcon(
                      FontAwesomeIcons.music,
                      size: 20,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            );
    } else {
      artworkWidget = QueryArtworkWidget(
        id: song.id,
        type: ArtworkType.AUDIO,
        size: 100,
        nullArtworkWidget: Container(
          width: 48,
          height: 48,
          color: Colors.grey.shade800,
          child: const FaIcon(FontAwesomeIcons.music, color: Colors.grey),
        ),
      );
    }

    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! < -10) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            barrierColor: Colors.black.withValues(alpha: 0.5),
            builder: (context) => const FullPlayer(),
          );
        }
      },
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          barrierColor: Colors.black.withValues(alpha: 0.5),
          builder: (context) => const FullPlayer(),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 12.0, top: 4.0),
        decoration: BoxDecoration(
          color: _bgColor.withOpacity(0.95),
          borderRadius: BorderRadius.circular(16.0),
        ),
        height: 64,
        child: Row(
          children: [
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: artworkWidget,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Consumer<PlaylistManager>(
              builder: (context, playlistManager, child) {
                final isFav = playlistManager.isFavorite(song.data);
                return IconButton(
                  icon: FaIcon(
                    isFav ? FontAwesomeIcons.solidHeart : FontAwesomeIcons.heart,
                    color: isFav ? AppColors.accent : Colors.white,
                  ),
                  onPressed: () {
                    playlistManager.toggleFavorite(song.data);
                  },
                );
              },
            ),
            StreamBuilder<bool>(
              stream: audioManager.audioPlayer.playingStream,
              builder: (context, snapshot) {
                final isPlaying = snapshot.data ?? false;
                return IconButton(
                  icon: FaIcon(
                    isPlaying ? FontAwesomeIcons.pause : FontAwesomeIcons.play,
                    color: Colors.white,
                    size: 32,
                  ),
                  onPressed: audioManager.togglePlayPause,
                );
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
