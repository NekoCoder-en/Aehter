import 'dart:io';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart' as ytmusic;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:path_provider/path_provider.dart';

import '../services/download_manager.dart';
import '../services/audio_manager.dart';
import '../services/music_brainz_service.dart';
import '../widgets/mini_player.dart';
import '../widgets/app_toast.dart';
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

  // just_audio_background solo permite un único AudioPlayer en toda la app,
  // así que la vista previa reusa el reproductor central de AudioManager
  // (que guarda/restaura lo que estaba sonando antes) en vez de crear uno propio.
  String? _previewingId;
  bool _previewLoading = false;
  // Cache de la sesión: si ya se descargó el preview de un video, se reusa
  // el archivo en vez de volver a bajarlo.
  final Map<String, String> _previewFileCache = {};

  @override
  void initState() {
    super.initState();
    _ytm.initialize();
    AudioManager().audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && _previewingId != null && mounted) {
        AudioManager().stopExternalPreview();
        setState(() => _previewingId = null);
      }
    });
  }

  Future<void> _togglePreview(Map<String, dynamic> songData) async {
    final id = songData['id'] as String;
    final audioManager = AudioManager();

    if (_previewingId == id) {
      await audioManager.stopExternalPreview();
      if (mounted) setState(() => _previewingId = null);
      return;
    }

    setState(() {
      _previewingId = id;
      _previewLoading = true;
    });

    try {
      final localPath = await _getPreviewFile(id);
      if (!mounted) return;
      await audioManager.playExternalPreview(
        localPath,
        title: songData['title'] as String? ?? 'Vista previa',
        artist: songData['author'] as String?,
        isLocalFile: true,
      );
      if (!mounted) return;
      setState(() => _previewLoading = false);
    } catch (e) {
      print("Error reproduciendo vista previa: $e");
      if (mounted) {
        setState(() {
          _previewLoading = false;
          _previewingId = null;
        });
        AppToast.show(context, 'No se pudo reproducir la vista previa', type: AppToastType.error);
      }
    }
  }

  // Las URL de streaming de YouTube quedan atadas a los headers/cliente que
  // las generó: pasárselas directo a ExoPlayer (ej. AudioSource.uri) da 403.
  // El resto de la app ya evita esto descargando los bytes con el cliente de
  // youtube_explode_dart (igual que _downloadAlbum/DownloadService), así que
  // acá hacemos lo mismo: bajamos el preview a un archivo temporal y lo
  // reproducimos desde ahí.
  Future<String> _getPreviewFile(String id) async {
    // Solo confiamos en el archivo si YA lo bajamos con éxito en esta misma
    // sesión (este mapa se llena al final de este método). No reusamos
    // archivos que ya existan en el disco de una corrida anterior: podrían
    // haber quedado corruptos/incompletos por un intento fallido previo.
    final cached = _previewFileCache[id];
    if (cached != null && File(cached).existsSync()) return cached;

    final manifest = await _yt.videos.streamsClient.getManifest(id);
    // Los streams "audio-only" de YouTube son fragmentos DASH: escribir sus
    // bytes crudos a un archivo no produce un mp4 válido y ExoPlayer no lo
    // puede leer ("NoDeclaredBrand"). El resto de la app (descarga de
    // canciones) ya evita esto usando el stream "muxed" (progresivo,
    // video+audio en un solo archivo reproducible tal cual) — hacemos igual.
    // Elegimos el de MENOR bitrate a propósito (no hace falta calidad para
    // una vista previa) para que la porción que bajamos pese lo menos posible.
    final muxedStreams = manifest.muxed.toList()
      ..sort((a, b) => a.bitrate.bitsPerSecond.compareTo(b.bitrate.bitsPerSecond));
    final streamInfo = muxedStreams.first;

    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/preview_$id.${streamInfo.container.name}';
    final file = File(filePath);

    // No hace falta bajar la canción/video entera para una vista previa: nos
    // quedamos solo con los primeros ~25-30s de contenido, así arranca rápido
    // sin importar cuán larga sea. Al hacer "break" dentro del "await for" se
    // cancela la descarga en el servidor, no se sigue gastando datos de más.
    const maxPreviewBytes = 1200000; // ~1.2MB
    final stream = _yt.videos.streamsClient.get(streamInfo);
    final fileStream = file.openWrite();
    int written = 0;
    await for (final data in stream) {
      fileStream.add(data);
      written += data.length;
      if (written >= maxPreviewBytes) break;
    }
    await fileStream.flush();
    await fileStream.close();

    _previewFileCache[id] = filePath;
    return filePath;
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
              'type': 'song',
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
              'type': 'video',
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
        AppToast.show(context, 'Error al buscar: $e', type: AppToastType.error);
      }
    }
  }

  void _startDownload(Map<String, dynamic> songData, {int? itag}) {
    context.read<DownloadManager>().addVideoDownload(
          songData['id'],
          songData['title'],
          artworkUrl: songData['thumbnail'],
          itag: itag,
        );
    AppToast.show(
      context,
      'Añadido a la cola: ${songData['title']}',
      type: AppToastType.success,
      duration: const Duration(seconds: 2),
    );
  }

  void _startAudioDownload(Map<String, dynamic> songData) {
    context.read<DownloadManager>().addDownload(
          songData['id'],
          songData['title'],
          artworkUrl: songData['thumbnail'],
          artistName: songData['author'],
        );
    AppToast.show(
      context,
      'Añadido a la cola: ${songData['title']}',
      type: AppToastType.success,
      duration: const Duration(seconds: 2),
    );
  }

  void _showDownloadOptions(Map<String, dynamic> songData) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
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
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Text(
                    songData['title'],
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const FaIcon(FontAwesomeIcons.music, color: AppColors.primary, size: 20),
                  title: const Text('Solo audio (MP3)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _startAudioDownload(songData);
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.0),
                  child: Divider(color: Colors.white12, height: 16),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Video', style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
                FutureBuilder<StreamManifest>(
                  future: _yt.videos.streamsClient.getManifest(songData['id']),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                      );
                    }
                    if (!snapshot.hasData) {
                      return Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Text('No se pudieron cargar las calidades de video', style: TextStyle(color: Colors.grey.shade500)),
                      );
                    }

                    final muxed = snapshot.data!.muxed.toList()
                      ..sort((a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));

                    if (muxed.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Text('No hay calidades de video disponibles', style: TextStyle(color: Colors.grey.shade500)),
                      );
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: muxed
                          .map((s) => ListTile(
                                leading: const FaIcon(FontAwesomeIcons.video, color: Colors.white, size: 20),
                                title: Text(s.qualityLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                                subtitle: Text(
                                  '${s.size.totalMegaBytes.toStringAsFixed(1)} MB',
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                                ),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _startDownload(songData, itag: s.tag);
                                },
                              ))
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _downloadAlbum(MusicBrainzAlbum album) async {
    AppToast.show(context, 'Procesando álbum: ${album.title}...', type: AppToastType.info);

    try {
      final artist = album.artist ?? 'Unknown Artist';
      final tracks = await _musicBrainz.getAlbumTracks(album.id, artist);

      if (tracks.isEmpty) {
        if (mounted) {
          AppToast.show(context, 'No se encontraron canciones en este álbum', type: AppToastType.error);
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
        AppToast.show(context, 'Se añadieron $addedCount canciones a la cola', type: AppToastType.success);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'Error al procesar el álbum: $e', type: AppToastType.error);
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
    if (_previewingId != null) {
      AudioManager().stopExternalPreview();
    }
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
                      if (!_searchAlbumsMode) {
                        setState(() {
                          _searchAlbumsMode = true;
                          _searchResults.clear();
                          _albumResults.clear();
                        });
                        if (_searchController.text.isNotEmpty) _search(_searchController.text);
                      }
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
                              
                              final isVideo = songData['type'] == 'video';
                              final isPreviewing = _previewingId == songData['id'];
                              final isPreviewLoading = isPreviewing && _previewLoading;

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                leading: GestureDetector(
                                  onTap: () => _togglePreview(songData),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: CachedNetworkImage(
                                          imageUrl: songData['thumbnail'],
                                          width: 60,
                                          height: 60,
                                          fit: BoxFit.cover,
                                          errorWidget: (context, url, error) => Container(
                                            width: 60,
                                            height: 60,
                                            color: Colors.grey.shade800,
                                            child: const Center(
                                              child: FaIcon(FontAwesomeIcons.music, color: Colors.grey, size: 24),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Overlay tenue con el ícono de reproducir/pausar la vista previa.
                                      Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: isPreviewing ? 0.45 : 0.25),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Center(
                                          child: isPreviewLoading
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                )
                                              : FaIcon(
                                                  isPreviewing ? FontAwesomeIcons.pause : FontAwesomeIcons.play,
                                                  color: Colors.white,
                                                  size: 18,
                                                ),
                                        ),
                                      ),
                                      if (isVideo)
                                        const Positioned(
                                          left: 2,
                                          top: 2,
                                          child: FaIcon(FontAwesomeIcons.video, color: Colors.white70, size: 11),
                                        ),
                                    ],
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
                                        : activeTask?.hasError == true
                                            ? IconButton(
                                                icon: const FaIcon(FontAwesomeIcons.triangleExclamation, color: Colors.redAccent, size: 20),
                                                tooltip: 'Error al descargar, toca para reintentar',
                                                onPressed: () {
                                                  context.read<DownloadManager>().clearError(songData['id']);
                                                  AppToast.show(context, 'Error al descargar. Probá de nuevo', type: AppToastType.error);
                                                  _showDownloadOptions(songData);
                                                },
                                              )
                                            : IconButton(
                                                icon: const FaIcon(FontAwesomeIcons.download, color: Colors.white, size: 20),
                                                onPressed: () => _showDownloadOptions(songData),
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
