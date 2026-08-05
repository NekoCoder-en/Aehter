import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../services/playlist_manager.dart';
import '../services/audio_manager.dart';
import '../widgets/full_player.dart';
import '../theme/app_colors.dart';
import 'video_list_view.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          title: const Text('Biblioteca', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          bottom: const TabBar(
            indicatorColor: AppColors.accent,
            labelColor: AppColors.accent,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'Playlists'),
              Tab(text: 'Videos'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildPlaylistsTab(),
            const VideoListView(),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistsTab() {
    return Consumer<PlaylistManager>(
      builder: (context, playlistManager, child) {
        final audioManager = context.watch<AudioManager>();
        final favorites = playlistManager.playlists['Favoritos'] ?? [];
        final customPlaylists = playlistManager.playlists.keys.where((k) => k != 'Favoritos').toList();
        final hiddenSongsCount = audioManager.hiddenSongs.length;
          
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildLibraryItem(
                context,
                title: 'Canciones favoritas',
                subtitle: '${favorites.length} canciones',
                icon: Icons.favorite,
                iconColor: AppColors.accent,
                songPaths: favorites,
              ),
              if (hiddenSongsCount > 0) ...[
                const SizedBox(height: 16),
                _buildHiddenSongsItem(context, hiddenSongsCount),
              ],
              const SizedBox(height: 16),
              const Text('Playlists', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (customPlaylists.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24.0),
                  child: Center(
                    child: Text("Aún no tienes playlists creadas", style: TextStyle(color: Colors.grey.shade500)),
                  ),
                ),
              ...customPlaylists.map((playlistName) {
                final songs = playlistManager.playlists[playlistName]!;
                return _buildLibraryItem(
                  context,
                  title: playlistName,
                  subtitle: '${songs.length} canciones',
                  icon: Icons.list,
                  iconColor: Colors.white,
                  songPaths: songs,
                );
              }).toList(),
              const SizedBox(height: 100),
            ],
          );
        },
      );
  }

  Widget _buildLibraryItem(BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required List<String> songPaths,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Icon(icon, color: iconColor, size: 24),
        ),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PlaylistDetailScreen(title: title, songPaths: songPaths),
          ),
        );
      },
    );
  }

  Widget _buildHiddenSongsItem(BuildContext context, int count) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Icon(Icons.visibility_off, color: Colors.grey, size: 24),
        ),
      ),
      title: const Text('Canciones ocultas', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
      subtitle: Text('$count canciones', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const HiddenSongsScreen(),
          ),
        );
      },
    );
  }
}

class PlaylistDetailScreen extends StatelessWidget {
  final String title;
  final List<String> songPaths;

  const PlaylistDetailScreen({super.key, required this.title, required this.songPaths});

  @override
  Widget build(BuildContext context) {
    final audioManager = context.watch<AudioManager>();
    // Filter the full songs list to get SongModels for the given paths
    final playlistSongs = audioManager.songs.where((s) => songPaths.contains(s.data)).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: playlistSongs.isEmpty
          ? Center(child: Text("No hay canciones en esta lista", style: TextStyle(color: Colors.grey.shade500)))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: playlistSongs.length,
              itemBuilder: (context, index) {
                final song = playlistSongs[index];
                final metadata = audioManager.simulatedMetadata[song.data];
                final artist = metadata != null ? metadata['artist'] : (song.artist ?? "Desconocido");
                final songTitle = metadata != null ? metadata['title'] : song.title;
                final artworkUrl = metadata != null ? metadata['artworkUrl'] : null;

                Widget artworkWidget;
                if (artworkUrl != null) {
                  artworkWidget = ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: artworkUrl.startsWith('file://')
                      ? Image.file(File(artworkUrl.replaceFirst('file://', '')), width: 50, height: 50, fit: BoxFit.cover)
                      : Image.network(
                          artworkUrl,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => QueryArtworkWidget(
                            id: song.id,
                            type: ArtworkType.AUDIO,
                            artworkWidth: 50,
                            artworkHeight: 50,
                            size: 200,
                            nullArtworkWidget: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade800,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Center(
                                child: FaIcon(FontAwesomeIcons.music, color: Colors.grey, size: 20),
                              ),
                            ),
                          ),
                        ),
                  );
                } else {
                  artworkWidget = QueryArtworkWidget(
                    id: song.id,
                    type: ArtworkType.AUDIO,
                    nullArtworkWidget: Container(
                      width: 50, height: 50, color: Colors.grey.shade800,
                      child: const Center(child: FaIcon(FontAwesomeIcons.music, color: Colors.grey, size: 20)),
                    ),
                  );
                }

                return ListTile(
                  leading: artworkWidget,
                  title: Text(songTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade400)),
                  trailing: const FaIcon(FontAwesomeIcons.ellipsisVertical, color: Colors.grey, size: 16),
                  onTap: () {
                    // Play the song in the global context
                    final globalIndex = audioManager.songs.indexWhere((s) => s.id == song.id);
                    if (globalIndex != -1) {
                      audioManager.playQueue(playlistSongs, index);
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        barrierColor: Colors.black.withOpacity(0.5),
                        builder: (context) => const FullPlayer(),
                      );
                    }
                  },
                );
              },
            ),
    );
  }
}

class HiddenSongsScreen extends StatelessWidget {
  const HiddenSongsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final audioManager = context.watch<AudioManager>();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Canciones ocultas'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: FutureBuilder<List<SongModel>>(
        future: audioManager.getHiddenSongModels(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.accent));
          }
          
          final hiddenSongs = snapshot.data ?? [];
          
          if (hiddenSongs.isEmpty) {
            return Center(child: Text("No hay canciones ocultas", style: TextStyle(color: Colors.grey.shade500)));
          }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 100),
            itemCount: hiddenSongs.length,
            itemBuilder: (context, index) {
              final song = hiddenSongs[index];
              final metadata = audioManager.simulatedMetadata[song.data];
              final artist = metadata != null ? metadata['artist'] : (song.artist ?? "Desconocido");
              final songTitle = metadata != null ? metadata['title'] : song.title;
              final artworkUrl = metadata != null ? metadata['artworkUrl'] : null;

              Widget artworkWidget;
              if (artworkUrl != null) {
                artworkWidget = ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: artworkUrl.startsWith('file://')
                      ? Image.file(File(artworkUrl.replaceFirst('file://', '')), width: 50, height: 50, fit: BoxFit.cover)
                      : Image.network(
                          artworkUrl,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => QueryArtworkWidget(
                            id: song.id,
                            type: ArtworkType.AUDIO,
                            artworkWidth: 50,
                            artworkHeight: 50,
                            size: 200,
                            nullArtworkWidget: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade800,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Center(
                                child: FaIcon(FontAwesomeIcons.music, color: Colors.grey, size: 20),
                              ),
                            ),
                          ),
                        ),
                );
              } else {
                artworkWidget = QueryArtworkWidget(
                  id: song.id,
                  type: ArtworkType.AUDIO,
                  nullArtworkWidget: Container(
                    width: 50, height: 50, color: Colors.grey.shade800,
                    child: const Center(child: FaIcon(FontAwesomeIcons.music, color: Colors.grey, size: 20)),
                  ),
                );
              }

              return ListTile(
                leading: artworkWidget,
                title: Text(songTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                subtitle: Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade400)),
                trailing: const Icon(Icons.visibility, color: AppColors.accent),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: const Color(0xFF282828),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                    builder: (bottomSheetContext) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.visibility, color: Colors.white),
                            title: const Text('Volver a mostrar esta canción', style: TextStyle(color: Colors.white)),
                            onTap: () {
                              Navigator.pop(bottomSheetContext);
                              audioManager.unhideSong(song.data);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Canción visible: $songTitle')),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
