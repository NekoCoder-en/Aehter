import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/playlist_manager.dart';
import '../../theme/app_colors.dart';
import 'artist_circles.dart';

class PlayerBottomSheets {
  static void showOptions(
    BuildContext context,
    SongModel song,
    String title,
    String artist,
    Widget artworkWidget,
    PlaylistManager playlistManager,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF282828),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                // Header with artwork and title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      SizedBox(width: 50, height: 50, child: artworkWidget),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              artist,
                              style: const TextStyle(color: Colors.grey, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                ArtistCircles(rawArtists: artist),
                const Divider(color: Colors.white24, height: 1),
                ListTile(
                  leading: FaIcon(
                    playlistManager.isFavorite(song.data) ? FontAwesomeIcons.solidHeart : FontAwesomeIcons.heart,
                    color: playlistManager.isFavorite(song.data) ? AppColors.accent : Colors.white,
                  ),
                  title: Text(
                    playlistManager.isFavorite(song.data) ? 'Eliminar de Favoritos' : 'Agregar a Favoritos',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    playlistManager.toggleFavorite(song.data);
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const FaIcon(FontAwesomeIcons.plus, color: Colors.white),
                  title: const Text('Agregar a la playlist', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    showPlaylists(context, song, playlistManager);
                  },
                ),
                ListTile(
                  leading: const FaIcon(FontAwesomeIcons.share, color: Colors.white),
                  title: const Text('Compartir', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    Share.shareXFiles([XFile(song.data)], text: 'Escucha $title!');
                  },
                ),
                ListTile(
                  leading: const FaIcon(FontAwesomeIcons.circleInfo, color: Colors.white),
                  title: const Text('Ver detalles', style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    song.data,
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(context),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  static void showPlaylists(
    BuildContext context,
    SongModel song,
    PlaylistManager playlistManager,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF282828),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              const Text(
                'Agregar a Playlist',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Divider(color: Colors.white24, height: 32),
              ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                  child: const Icon(Icons.add, color: Colors.white),
                ),
                title: const Text('Nueva playlist', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  showCreatePlaylistDialog(context, song, playlistManager);
                },
              ),
              ...playlistManager.playlists.keys.where((k) => k != 'Favoritos').map((playlistName) {
                return ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: Colors.grey.shade800, borderRadius: BorderRadius.circular(4)),
                    child: const Icon(Icons.queue_music, color: Colors.white),
                  ),
                  title: Text(playlistName, style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    playlistManager.addToPlaylist(playlistName, song.data);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Agregado a $playlistName')));
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  static void showCreatePlaylistDialog(
    BuildContext context,
    SongModel song,
    PlaylistManager playlistManager,
  ) {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF282828),
          title: const Text(
            'Dale un nombre a tu playlist',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            autofocus: true,
            decoration: const InputDecoration(
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  playlistManager.createPlaylist(name);
                  playlistManager.addToPlaylist(name, song.data);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Playlist creada')));
                }
              },
              child: const Text('Crear', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        );
      },
    );
  }
}
