import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart' as ytmusic;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../services/download_service.dart';
import '../services/download_manager.dart';
import '../services/audio_manager.dart';
import '../services/music_brainz_service.dart';
import '../widgets/mini_player.dart';
import '../theme/app_colors.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final TextEditingController _searchController = TextEditingController();
  final YoutubeExplode _yt = YoutubeExplode();
  final ytmusic.YTMusic _ytm = ytmusic.YTMusic();
  final MusicBrainzService _musicBrainz = MusicBrainzService();
  
  List<Map<String, dynamic>> _searchResults = [];
  List<MusicBrainzAlbum> _albumResults = [];
  bool _isSearching = false;
  bool _searchAlbumsMode = false;

  @override
  void initState() {
    super.initState();
    _ytm.initialize();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchResults.clear();
      _albumResults.clear();
    });

    try {
      if (_searchAlbumsMode) {
        final results = await _musicBrainz.searchAlbums(query);
        setState(() {
          _albumResults = results;
          _isSearching = false;
        });
      } else {
        final results = await _ytm.search(query);
        final List<Map<String, dynamic>> parsedResults = [];
        for (var res in results) {
          if (res is ytmusic.SongDetailed) {
            parsedResults.add({
              'id': res.videoId,
              'title': res.name,
              'author': res.artist.name,
              'duration': Duration(seconds: res.duration ?? 0),
              'thumbnail': res.thumbnails.isNotEmpty 
                  ? res.thumbnails.last.url.replaceFirst(RegExp(r'=w\d+-h\d+'), '=w1080-h1080')
                  : "https://i.ytimg.com/vi/${res.videoId}/maxresdefault.jpg",
            });
          } else if (res is ytmusic.VideoDetailed) {
            parsedResults.add({
              'id': res.videoId,
              'title': res.name,
              'author': res.artist.name,
              'duration': Duration(seconds: res.duration ?? 0),
              'thumbnail': res.thumbnails.isNotEmpty 
                  ? res.thumbnails.last.url.replaceFirst(RegExp(r'=w\d+-h\d+'), '=w1080-h1080')
                  : "https://i.ytimg.com/vi/${res.videoId}/maxresdefault.jpg",
            });
          }
        }
        setState(() {
          _searchResults = parsedResults;
          _isSearching = false;
        });
      }
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al buscar: $e')),
        );
      }
    }
  }

  Future<void> _downloadAlbum(MusicBrainzAlbum album) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Procesando álbum: ${album.title}...')),
    );

    try {
      final artist = album.artist ?? 'Unknown Artist';
      final tracks = await _musicBrainz.getAlbumTracks(album.id, artist);
      
      if (tracks.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se encontraron canciones en este álbum')),
          );
        }
        return;
      }

      int addedCount = 0;
      for (final track in tracks) {
        // Buscar cada canción en YouTube silenciosamente
        final query = "${track.artist} ${track.title}";
        final results = await _yt.search.search(query);
        if (results.isNotEmpty) {
          final video = results.first;
          if (mounted) {
            context.read<DownloadManager>().addDownload(
              video.id.value,
              "${track.artist} - ${track.title}", // Guardar con nombre limpio
              artworkUrl: video.thumbnails.highResUrl,
            );
            addedCount++;
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Se añadieron $addedCount canciones a la cola')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al procesar el álbum: $e')),
        );
      }
    }
  }



  String _formatDuration(Duration? duration) {
    if (duration == null) return "0:00";
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${duration.inHours}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "${duration.inMinutes}:$twoDigitSeconds";
  }

  @override
  void dispose() {
    _searchController.dispose();
    _yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audioManager = context.watch<AudioManager>();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        title: const Text('Explorar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Toggle Search Mode
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: !_searchAlbumsMode ? AppColors.primary : Colors.grey.shade900,
                      foregroundColor: !_searchAlbumsMode ? Colors.black : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      if (_searchAlbumsMode) {
                        setState(() {
                          _searchAlbumsMode = false;
                          _searchResults.clear();
                          _albumResults.clear();
                        });
                        if (_searchController.text.isNotEmpty) _search(_searchController.text);
                      }
                    },
                    child: const Text("Canciones"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _searchAlbumsMode ? AppColors.primary : Colors.grey.shade900,
                      foregroundColor: _searchAlbumsMode ? Colors.black : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      // Funcionalidad deshabilitada por petición del usuario
                    },
                    child: const Text("Álbumes"),
                  ),
                ),
              ],
            ),
          ),
          
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: _searchAlbumsMode ? 'Buscar álbumes...' : 'Buscar canciones...',
                hintStyle: TextStyle(color: Colors.grey.shade500),
                prefixIcon: FaIcon(FontAwesomeIcons.magnifyingGlass, color: Colors.grey.shade500, size: 18),
                filled: true,
                fillColor: Colors.grey.shade900,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchResults.clear();
                      _albumResults.clear();
                    });
                  },
                ),
              ),
              onSubmitted: _search,
            ),
          ),

          // Results
          Expanded(
            child: _isSearching
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : (_searchAlbumsMode ? _albumResults.isEmpty : _searchResults.isEmpty)
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FaIcon(_searchAlbumsMode ? FontAwesomeIcons.compactDisc : FontAwesomeIcons.music, size: 64, color: Colors.grey.shade800),
                            const SizedBox(height: 16),
                            Text(
                              _searchAlbumsMode ? "Busca álbumes completos" : "Busca música para descargar",
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : _searchAlbumsMode 
                        ? ListView.builder(
                            itemCount: _albumResults.length,
                            itemBuilder: (context, index) {
                              final album = _albumResults[index];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                leading: Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade800,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Center(child: FaIcon(FontAwesomeIcons.compactDisc, color: Colors.grey)),
                                ),
                                title: Text(
                                  album.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    "${album.artist ?? 'Varios Artistas'} • ${album.releaseDate ?? 'Año desconocido'}",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const FaIcon(FontAwesomeIcons.download, color: Colors.white, size: 20),
                                  onPressed: () => _downloadAlbum(album),
                                ),
                              );
                            },
                          )
                        : ListView.builder(
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final songData = _searchResults[index];
                              final downloadManager = context.watch<DownloadManager>();
                              
                              final activeTask = downloadManager.queue.where((task) => task.id == songData['id']).firstOrNull;
                              final isDownloading = activeTask != null && (activeTask.isDownloading || (!activeTask.isCompleted && !activeTask.hasError));
                              final progress = activeTask?.progress ?? 0.0;
                              
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.network(
                                    songData['thumbnail'],
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      width: 60,
                                      height: 60,
                                      color: Colors.grey.shade800,
                                      child: const Center(
                                        child: FaIcon(FontAwesomeIcons.music, color: Colors.grey, size: 24),
                                      ),
                                    ),
                                  ),
                                ),
                                title: Text(
                                  songData['title'],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    "${songData['author']} • ${_formatDuration(songData['duration'])}",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                                  ),
                                ),
                                trailing: isDownloading
                                    ? SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: Center(
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              CircularProgressIndicator(
                                                value: progress > 0 ? progress : null,
                                                color: AppColors.primary,
                                                backgroundColor: Colors.grey.shade800,
                                              ),
                                              if (progress == 0)
                                                const Text("...", style: TextStyle(color: Colors.white, fontSize: 10))
                                              else
                                                Text("${(progress * 100).toInt()}%", style: const TextStyle(color: Colors.white, fontSize: 10)),
                                            ],
                                          ),
                                        ),
                                      )
                                    : activeTask?.isCompleted == true 
                                        ? const FaIcon(FontAwesomeIcons.check, color: AppColors.primary, size: 20)
                                        : IconButton(
                                            icon: const FaIcon(FontAwesomeIcons.download, color: Colors.white, size: 20),
                                            onPressed: () {
                                              context.read<DownloadManager>().addDownload(
                                                songData['id'],
                                                songData['title'],
                                                artworkUrl: songData['thumbnail'],
                                                artistName: songData['author'],
                                              );
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Añadido a la cola: ${songData['title']}'),
                                                  duration: const Duration(seconds: 2),
                                                ),
                                              );
                                            },
                                          ),
                              );
                            },
                          ),
          ),
          
          if (audioManager.currentSong != null)
            const MiniPlayer(),
        ],
      ),
    );
  }
}
