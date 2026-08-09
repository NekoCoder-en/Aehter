import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/audio_manager.dart';
import '../services/download_manager.dart';
import '../widgets/mini_player.dart';
import '../widgets/app_toast.dart';
import '../theme/app_colors.dart';

import 'explore_screen.dart';
import 'library_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  bool _hasPermission = false;
  int _selectedIndex = 0;
  String _searchQuery = '';
  late final AnimationController _syncIconController;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _syncIconController = AnimationController(vsync: this, duration: const Duration(seconds: 1));
  }

  @override
  void dispose() {
    _syncIconController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    PermissionStatus audioStatus = await Permission.audio.status;
    PermissionStatus storageStatus = await Permission.storage.status;

    if (audioStatus.isGranted || storageStatus.isGranted) {
      _grantPermission();
      return;
    }

    Map<Permission, PermissionStatus> statuses = await [
      Permission.storage,
      Permission.audio,
      Permission.notification,
    ].request();

    if (statuses[Permission.audio] == PermissionStatus.granted ||
        statuses[Permission.storage] == PermissionStatus.granted) {
      _grantPermission();
    } else {
      setState(() => _hasPermission = false);
    }
  }

  void _grantPermission() {
    setState(() => _hasPermission = true);
    if (mounted) {
      context.read<AudioManager>().loadSongs();
    }
  }

  Widget _buildHomeContent(AudioManager audioManager) {
    final filteredSongs = audioManager.songs.where((song) {
      if (_searchQuery.isEmpty) return true;
      final metadata = audioManager.simulatedMetadata[song.data];
      final title = (metadata != null ? metadata['title'] : song.title)?.toString().toLowerCase() ?? "";
      final artist = (metadata != null ? metadata['artist'] : (song.artist ?? "Desconocido")).toString().toLowerCase();
      return title.contains(_searchQuery.toLowerCase()) || artist.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inicio', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          audioManager.isSyncingCovers
              ? Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: RotationTransition(
                    turns: _syncIconController,
                    child: const Icon(Icons.sync, color: AppColors.primary, size: 22),
                  ),
                )
              : PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  color: const Color(0xFF282828),
                  onSelected: (value) {
                    if (value == 'update_covers') {
                      _updateCovers(context, audioManager);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'update_covers',
                      child: Text('Actualizar portadas', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
        ],
      ),
      backgroundColor: const Color(0xFF121212),
      body: !_hasPermission
          ? Center(
              child: ElevatedButton(
                onPressed: _checkPermissions,
                child: const Text("Permitir acceso a música"),
              ),
            )
          : audioManager.songs.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    Column(
                      children: [
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          child: audioManager.isSyncingCovers
                              ? const LinearProgressIndicator(
                                  minHeight: 3,
                                  color: AppColors.primary,
                                  backgroundColor: Colors.transparent,
                                )
                              : const SizedBox(width: double.infinity, height: 0),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          child: TextField(
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Buscar canciones o artistas...',
                              hintStyle: TextStyle(color: Colors.grey.shade600),
                              prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                              filled: true,
                              fillColor: Colors.grey.shade900,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.0),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (value) => setState(() => _searchQuery = value),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: EdgeInsets.only(bottom: audioManager.currentSong != null ? 80 : 20),
                            itemCount: filteredSongs.length,
                            itemBuilder: (context, index) {
                              final song = filteredSongs[index];
                              // Find the global index for playback
                              final globalIndex = audioManager.songs.indexOf(song);
                              final isPlaying = audioManager.currentSong?.id == song.id;
                              
                              final metadata = audioManager.simulatedMetadata[song.data];
                              final artist = metadata != null ? metadata['artist'] : (song.artist ?? "Desconocido");
                              final title = metadata != null ? metadata['title'] : song.title;
                              final artworkUrl = metadata != null ? metadata['artworkUrl'] : null;

                              Widget artworkWidget;
                              if (artworkUrl != null) {
                                 artworkWidget = ClipRRect(
                                   borderRadius: BorderRadius.circular(4),
                                   child: artworkUrl.startsWith('file://')
                                    ? Image.file(File(artworkUrl.replaceFirst('file://', '')), width: 50, height: 50, fit: BoxFit.cover)
                                     : CachedNetworkImage(
                                         imageUrl: artworkUrl,
                                         width: 50,
                                         height: 50,
                                         fit: BoxFit.cover,
                                         errorWidget: (context, url, error) => QueryArtworkWidget(
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
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade800,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const FaIcon(FontAwesomeIcons.music, color: Colors.grey),
                                  ),
                                );
                              }

                              return ListTile(
                                leading: artworkWidget,
                                title: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isPlaying ? AppColors.primary : Colors.white,
                                    fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Text(
                                  artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.grey),
                                ),
                                onTap: () {
                                  audioManager.playSong(globalIndex);
                                },
                                onLongPress: () {
                                  showModalBottomSheet(
                                    context: context,
                                    backgroundColor: const Color(0xFF282828),
                                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                                    builder: (context) => SafeArea(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ListTile(
                                            leading: const Icon(Icons.visibility_off, color: Colors.white),
                                            title: const Text('Ocultar canción', style: TextStyle(color: Colors.white)),
                                            onTap: () {
                                              Navigator.pop(context);
                                              audioManager.hideSong(song.data);
                                              AppToast.show(context, 'Canción ocultada: $title', type: AppToastType.success);
                                            },
                                          ),
                                          ListTile(
                                            leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                            title: const Text('Eliminar canción', style: TextStyle(color: Colors.redAccent)),
                                            onTap: () {
                                              Navigator.pop(context);
                                              _confirmDeleteSong(context, audioManager, song.data, title);
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    if (audioManager.currentSong != null)
                      const Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: MiniPlayer(),
                      ),
                  ],
                ),
    );
  }

  void _updateCovers(BuildContext context, AudioManager audioManager) {
    _syncIconController.repeat();
    AppToast.show(context, 'Actualizando portadas...', type: AppToastType.info);
    audioManager.syncMissingCovers().then((_) async {
      _syncIconController.stop();
      if (!mounted) return;
      // Refresca la pantalla de inicio para reflejar las portadas nuevas.
      await audioManager.loadSongs();
      if (!mounted) return;
      AppToast.show(context, 'Portadas actualizadas', type: AppToastType.success);
    });
  }

  void _confirmDeleteSong(BuildContext context, AudioManager audioManager, String path, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text('Eliminar canción', style: TextStyle(color: Colors.white)),
        content: Text(
          '¿Seguro que quieres eliminar "$title" de tu dispositivo? Esta acción no se puede deshacer.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              audioManager.deleteSong(path);
              AppToast.show(context, 'Canción eliminada: $title', type: AppToastType.success);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showDownloads(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return Consumer<DownloadManager>(
          builder: (context, downloadManager, child) {
            final queue = downloadManager.queue;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Descargas Activas", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      TextButton(
                        onPressed: downloadManager.clearCompleted,
                        child: const Text("Limpiar completadas", style: TextStyle(color: AppColors.primary)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: queue.isEmpty
                      ? Center(child: Text("No hay descargas", style: TextStyle(color: Colors.grey.shade500)))
                      : ListView.builder(
                          itemCount: queue.length,
                          itemBuilder: (context, index) {
                            final task = queue[index];
                            return ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: task.artworkUrl != null
                                    ? (task.artworkUrl!.startsWith('file://')
                                      ? Image.file(File(task.artworkUrl!.replaceFirst('file://', '')), width: 40, height: 40, fit: BoxFit.cover)
                                      : CachedNetworkImage(
                                          imageUrl: task.artworkUrl!,
                                          width: 40,
                                          height: 40,
                                          fit: BoxFit.cover,
                                          errorWidget: (context, url, error) => Container(
                                            width: 40,
                                            height: 40,
                                            color: Colors.grey.shade800,
                                            child: const Center(
                                              child: FaIcon(FontAwesomeIcons.music, color: Colors.grey, size: 16),
                                            ),
                                          ),
                                        ))
                                    : Container(width: 40, height: 40, color: Colors.grey.shade800),
                              ),
                              title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              subtitle: task.isCompleted
                                  ? const Text("Completado", style: TextStyle(color: AppColors.primary))
                                  : task.hasError
                                      ? const Text("Error", style: TextStyle(color: Colors.red))
                                      : task.isDownloading
                                          ? LinearProgressIndicator(value: task.progress > 0 ? task.progress : null, color: AppColors.primary)
                                          : const Text("En cola...", style: TextStyle(color: Colors.grey)),
                              trailing: task.isCompleted
                                  ? const FaIcon(FontAwesomeIcons.check, color: AppColors.primary, size: 16)
                                  : task.hasError
                                      ? const FaIcon(FontAwesomeIcons.xmark, color: Colors.red, size: 16)
                                      : Text("${(task.progress * 100).toInt()}%", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final audioManager = context.watch<AudioManager>();

    final List<Widget> pages = [
      _buildHomeContent(audioManager),
      const ExploreScreen(),
      const LibraryScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      // Scoped a un Consumer propio: el progreso de descarga notifica muy seguido
      // (varias veces por segundo) y no debe reconstruir toda la pantalla de inicio.
      floatingActionButton: Consumer<DownloadManager>(
        builder: (context, downloadManager, child) {
          if (_selectedIndex != 1 || downloadManager.queue.isEmpty) return const SizedBox.shrink();
          return FloatingActionButton(
            backgroundColor: AppColors.primary,
            onPressed: () => _showDownloads(context),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const FaIcon(FontAwesomeIcons.download, color: Colors.black),
                if (downloadManager.hasActiveDownloads)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        "${downloadManager.activeDownloadsCount}",
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),

      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1A1A1A),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex >= pages.length ? 0 : _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: FaIcon(FontAwesomeIcons.house), label: 'Inicio'),
          BottomNavigationBarItem(icon: FaIcon(FontAwesomeIcons.compass), label: 'Explorar'),
          BottomNavigationBarItem(icon: FaIcon(FontAwesomeIcons.book), label: 'Biblioteca'),
        ],
      ),
    );
  }
}

