import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../services/audio_manager.dart';
import '../services/playlist_manager.dart';
import '../utils/image_utils.dart';

import 'karaoke_view.dart';
import '../theme/app_colors.dart';

// Components
import 'player/player_controls.dart';
import 'player/player_progress_bar.dart';
import 'player/player_queue_sheet.dart';
import 'player/player_bottom_sheets.dart';
import 'player/karaoke_button.dart';

class FullPlayer extends StatefulWidget {
  const FullPlayer({super.key});

  @override
  State<FullPlayer> createState() => _FullPlayerState();
}

class _FullPlayerState extends State<FullPlayer> {
  Color _bgColor = const Color(0xFF121212);
  int? _lastSongId;
  bool _isQueueExpanded = false;
  bool _showKaraoke = false;

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
    final playlistManager = context.watch<PlaylistManager>();
    final song = audioManager.currentSong;

    if (song == null) return const SizedBox.shrink();

    if (song.id != _lastSongId) {
      _updateColor();
    }

    final metadata = audioManager.simulatedMetadata[song.data];
    final artist = metadata != null ? metadata['artist'] : (song.artist ?? "Desconocido");
    final title = metadata != null ? metadata['title'] : song.title;
    final String? rawArtwork = metadata != null ? metadata['artworkUrl'] : null;
    final artworkUrl = rawArtwork?.replaceFirst(RegExp(r'=w\d+-h\d+'), '=w1080-h1080');

    Widget artworkWidget;
    if (artworkUrl != null) {
      artworkWidget = artworkUrl.startsWith('file://') 
        ? Image.file(
            File(artworkUrl.replaceFirst('file://', '')),
            width: MediaQuery.of(context).size.width - 48,
            height: MediaQuery.of(context).size.width - 48,
            fit: BoxFit.cover,
          )
        : Image.network(
        artworkUrl,
        width: MediaQuery.of(context).size.width - 48,
        height: MediaQuery.of(context).size.width - 48,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => QueryArtworkWidget(
          id: song.id,
          type: ArtworkType.AUDIO,
          artworkWidth: MediaQuery.of(context).size.width - 48,
          artworkHeight: MediaQuery.of(context).size.width - 48,
          size: 800,
          nullArtworkWidget: Container(
            width: MediaQuery.of(context).size.width - 48,
            height: MediaQuery.of(context).size.width - 48,
            color: Colors.grey.shade800,
            child: const Center(
              child: FaIcon(
                FontAwesomeIcons.wifi,
                size: 50,
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
        artworkWidth: MediaQuery.of(context).size.width - 48,
        artworkHeight: MediaQuery.of(context).size.width - 48,
        size: 800,
        nullArtworkWidget: Container(
          width: MediaQuery.of(context).size.width - 48,
          height: MediaQuery.of(context).size.width - 48,
          color: Colors.grey.shade800,
          child: const FaIcon(
            FontAwesomeIcons.music,
            size: 100,
            color: Colors.grey,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const FaIcon(
            FontAwesomeIcons.angleDown,
            size: 32,
            color: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Column(
          children: [
            Text(
              "MIX DE LA CANCIÓN",
              style: TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w400,
              ),
            ),
            Text(
              "REPRODUCIENDO",
              style: TextStyle(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const FaIcon(
              FontAwesomeIcons.ellipsisVertical,
              color: Colors.white,
            ),
            onPressed: () {
              PlayerBottomSheets.showOptions(
                context,
                song,
                title,
                artist,
                artworkWidget,
                playlistManager,
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Album Art
                  Hero(
                    tag: 'album_art_${song.id}',
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8.0),
                        child: Stack(
                          children: [
                            artworkWidget,
                            
                            // Karaoke Overlay on top of artwork
                            if (_showKaraoke)
                              Positioned.fill(
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                  child: KaraokeView(
                                    songPath: song.data,
                                    artist: artist,
                                    title: title,
                                    positionStream: audioManager.audioPlayer.positionStream,
                                    onClose: () => setState(() => _showKaraoke = false),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Title and Artist with Like Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const FaIcon(
                          FontAwesomeIcons.share,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          Share.shareXFiles([XFile(song.data)], text: 'Escucha $title!');
                        },
                      ),
                      Row(
                        children: [
                          KaraokeButton(
                            isActive: _showKaraoke,
                            onTap: () {
                              setState(() => _showKaraoke = !_showKaraoke);
                            },
                          ),
                          IconButton(
                            icon: const FaIcon(
                              FontAwesomeIcons.plus,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              PlayerBottomSheets.showPlaylists(context, song, playlistManager);
                            },
                          ),
                          IconButton(
                            icon: FaIcon(
                              playlistManager.isFavorite(song.data) 
                                ? FontAwesomeIcons.solidHeart 
                                : FontAwesomeIcons.heart,
                              color: playlistManager.isFavorite(song.data)
                                ? AppColors.accent
                                : Colors.white,
                            ),
                            onPressed: () {
                              playlistManager.toggleFavorite(song.data);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),

                  Column(
                    children: [
                      const PlayerProgressBar(),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "$artist - $title",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),

                  // Controls
                  const PlayerControls(),

                  const SizedBox(height: 80), // Space for queue handle
                ],
              ),
            ),
          ),

          // Animated Custom Queue Sheet
          PlayerQueueSheet(
            isExpanded: _isQueueExpanded,
            bgColor: _bgColor,
            onToggle: () => setState(() => _isQueueExpanded = !_isQueueExpanded),
            onDragUpdate: (details) {
              if (details.primaryDelta! > 10) {
                setState(() => _isQueueExpanded = false);
              } else if (details.primaryDelta! < -10) {
                setState(() => _isQueueExpanded = true);
              }
            },
          ),
        ],
      ),
    );
  }
}
