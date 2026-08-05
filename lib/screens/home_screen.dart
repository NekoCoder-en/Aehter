import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../services/audio_manager.dart';
import '../services/download_manager.dart';
import '../widgets/mini_player.dart';
import '../theme/app_colors.dart';

import 'explore_screen.dart';
import 'library_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hasPermission = false;
  int _selectedIndex = 0;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _checkPermissions();
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
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Canción ocultada: $title')),
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
                                      : Image.network(
                                          task.artworkUrl!,
                                          width: 40,
                                          height: 40,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
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
    final downloadManager = context.watch<DownloadManager>();

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
      floatingActionButton: _selectedIndex == 1 && downloadManager.queue.isNotEmpty
          ? FloatingActionButton(
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
            )
          : null,

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

