import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/playlist_manager.dart';
import '../../theme/app_colors.dart';
import '../app_toast.dart';
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
                const _DragHandle(),
                // Header with artwork and title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(width: 56, height: 56, child: artworkWidget),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
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
                const _SheetDivider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _QuickActionButton(
                        icon: playlistManager.isFavorite(song.data) ? FontAwesomeIcons.solidHeart : FontAwesomeIcons.heart,
                        iconColor: playlistManager.isFavorite(song.data) ? AppColors.accent : Colors.white,
                        label: playlistManager.isFavorite(song.data) ? 'Quitar' : 'Favoritos',
                        onTap: () {
                          playlistManager.toggleFavorite(song.data);
                          Navigator.pop(context);
                        },
                      ),
                      _QuickActionButton(
                        icon: FontAwesomeIcons.plus,
                        label: 'Playlist',
                        onTap: () {
                          Navigator.pop(context);
                          showPlaylists(context, song, playlistManager);
                        },
                      ),
                      _QuickActionButton(
                        icon: FontAwesomeIcons.share,
                        label: 'Compartir',
                        onTap: () {
                          Navigator.pop(context);
                          Share.shareXFiles([XFile(song.data)], text: 'Escucha $title!');
                        },
                      ),
                    ],
                  ),
                ),
                const _SheetDivider(),
                _ActionTile(
                  icon: FontAwesomeIcons.circleInfo,
                  title: 'Ver detalles',
                  subtitle: song.data,
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
              const _DragHandle(),
              const Text(
                'Agregar a Playlist',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const _SheetDivider(),
              _ActionTile(
                icon: FontAwesomeIcons.plus,
                title: 'Nueva playlist',
                onTap: () {
                  Navigator.pop(context);
                  showCreatePlaylistDialog(context, song, playlistManager);
                },
              ),
              ...playlistManager.playlists.keys.where((k) => k != 'Favoritos').map((playlistName) {
                return _ActionTile(
                  icon: FontAwesomeIcons.listUl,
                  title: playlistName,
                  onTap: () {
                    playlistManager.addToPlaylist(playlistName, song.data);
                    Navigator.pop(context);
                    AppToast.show(context, 'Agregado a $playlistName', type: AppToastType.success);
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
                  AppToast.show(context, 'Playlist creada', type: AppToastType.success);
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

/// Barra de arrastre estándar mostrada arriba de las hojas de este archivo.
class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 12, bottom: 8),
      child: SizedBox(
        width: 40,
        height: 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
        ),
      ),
    );
  }
}

class _SheetDivider extends StatelessWidget {
  const _SheetDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.0),
      child: Divider(color: Colors.white12, height: 1),
    );
  }
}

/// Fila de acción simple: ícono + texto, sin fondos de color, separadas por
/// líneas finas (`_SheetDivider`). Se usa para acciones de lista variable
/// (playlists, "Ver detalles") donde no aplica la fila de accesos rápidos.
class _ActionTile extends StatelessWidget {
  final FaIconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 2.0),
      leading: FaIcon(icon, color: Colors.white70, size: 20),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(color: Colors.grey, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      onTap: onTap,
    );
  }
}

/// Botón de acceso rápido (ícono + etiqueta debajo), sin fondo ni círculo,
/// usado para las 3 acciones principales de una canción.
class _QuickActionButton extends StatelessWidget {
  final FaIconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(icon, color: iconColor, size: 24),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
