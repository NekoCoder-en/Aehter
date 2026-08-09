import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:flutter/material.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart' as ytmusic;
import 'package:audiotags/audiotags.dart';
import 'package:dio/dio.dart' as dio_pkg;
import 'dart:typed_data';

class AudioManager extends ChangeNotifier {
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;

  final AudioPlayer audioPlayer = AudioPlayer();
  final OnAudioQuery audioQuery = OnAudioQuery();
  ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);

  AudioManager._internal() {
    audioPlayer.currentIndexStream.listen((index) {
      // Mientras se reproduce una vista previa externa (ej. Explorar), el
      // audioPlayer no está usando _playlist, así que hay que ignorar estos
      // eventos para no pisar currentIndex/"last_song_path" con basura.
      if (_isPreviewingExternal) return;

      if (index != null && index >= 0 && index < queue.length) {
        currentIndex = index;
        final songPath = queue[currentIndex].data;

        // Save last played song
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString('last_song_path', songPath);
        });

        notifyListeners();
      }
    });
  }

  List<SongModel> songs = [];
  List<SongModel> queue = [];
  Map<String, Map<String, dynamic>> simulatedMetadata = {};
  List<String> hiddenSongs = [];
  // Canciones eliminadas por el usuario: se excluyen igual que las ocultas,
  // pero en una lista separada para que NO aparezcan en "Canciones ocultas".
  List<String> deletedSongs = [];
  int currentIndex = -1;
  bool isSyncingCovers = false;

  // just_audio_background solo permite UNA instancia de AudioPlayer en toda
  // la app, así que la vista previa de Explorar tiene que reusar este mismo
  // reproductor en vez de crear uno propio. Estos campos guardan lo que
  // estaba sonando antes para poder restaurarlo al terminar la vista previa.
  bool _isPreviewingExternal = false;
  bool _previewWasPlaying = false;
  Duration? _previewSavedPosition;

  bool get isPreviewingExternal => _isPreviewingExternal;

  SongModel? get currentSong => currentIndex >= 0 && currentIndex < queue.length
      ? queue[currentIndex]
      : null;

  static const List<String> _unknownArtistValues = [
    'unknown artist',
    '<unknown>',
    'desconocido',
    'unknown',
    'n/a',
  ];

  bool _isUnknownArtist(String? a) {
    if (a == null) return true;
    final normalized = a.trim().toLowerCase();
    return normalized.isEmpty || _unknownArtistValues.contains(normalized);
  }

  Future<void> loadSongs() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/metadata_registry.json');
      if (file.existsSync()) {
        final Map<String, dynamic> data = jsonDecode(file.readAsStringSync());
        simulatedMetadata = data.map(
          (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
        );
      }
    } catch (e) {
      print("Error loading simulated metadata: $e");
    }

    final allSongs = await audioQuery.querySongs(
      sortType: null,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      hiddenSongs = prefs.getStringList('hidden_songs') ?? [];
      deletedSongs = prefs.getStringList('deleted_songs') ?? [];
    } catch (e) {
      print("Error loading hidden songs: $e");
    }

    songs = allSongs.where((song) {
      final title = song.title.toUpperCase();
      final fileName = song.data.toUpperCase();

      if (title.startsWith('AUD-') || fileName.contains('AUD-')) return false;
      if (title.contains('-WA') || fileName.contains('-WA')) return false;
      if (hiddenSongs.contains(song.data)) return false;
      if (deletedSongs.contains(song.data)) return false;

      return true;
    }).toList();

    // Generar o arreglar metadatos simulados para canciones viejas
    for (var song in songs) {
      final meta = simulatedMetadata[song.data];
      if (meta == null || _isUnknownArtist(meta['artist'] as String?)) {
        final filename = song.data
            .split('/')
            .last
            .replaceAll(RegExp(r'\.mp3|\.m4a'), '');
        String artist = song.artist ?? "Unknown Artist";
        if (_isUnknownArtist(artist)) artist = "Unknown Artist";
        String parsedTitle = song.title;

        if (_isUnknownArtist(artist)) {
          if (filename.contains(" - ")) {
            final parts = filename.split(" - ");
            artist = parts[0].trim();
            parsedTitle = parts.sublist(1).join(" - ").trim();
          } else if (filename.contains("-")) {
            final parts = filename.split("-");
            artist = parts[0].trim();
            parsedTitle = parts.sublist(1).join("-").trim();
          } else if (filename.contains("_")) {
            final parts = filename.split("_");
            artist = parts[0].trim();
            parsedTitle = parts.sublist(1).join("_").trim();
          } else {
            parsedTitle = filename;
          }
        }

        simulatedMetadata[song.data] = {
          'artist': artist,
          'title': parsedTitle,
          'artworkUrl': meta?['artworkUrl'],
        };
      }
    }

    // Restore last played song only if queue is empty (startup)
    if (queue.isEmpty && !audioPlayer.playing) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final lastSongPath = prefs.getString('last_song_path');
        if (lastSongPath != null && songs.isNotEmpty) {
          final index = songs.indexWhere((s) => s.data == lastSongPath);
          if (index != -1) {
            await playQueue(songs, index, autoPlay: false);
          }
        }
      } catch (e) {
        print("Error restoring last song: $e");
      }
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/metadata_registry.json');
      await file.writeAsString(jsonEncode(simulatedMetadata));
    } catch (e) {
      print("Error saving metadata registry: $e");
    }

    notifyListeners();
  }

  /// Busca y descarga portadas en alta resolución para las canciones que no
  /// tienen una o cuya versión local es de baja calidad. Se dispara manualmente
  /// desde el menú de la pantalla de inicio ("Actualizar portadas"), ya que
  /// recorrer la biblioteca canción por canción es lento para hacerlo cada vez
  /// que se abre la app.
  Future<void> syncMissingCovers() async {
    if (isSyncingCovers) return;
    isSyncingCovers = true;
    notifyListeners();

    try {
      await _syncMissingCoversInBackground();
    } finally {
      isSyncingCovers = false;
      notifyListeners();
    }
  }

  Future<void> _syncMissingCoversInBackground() async {
    final docDir = await getApplicationDocumentsDirectory();
    final coversDir = Directory('${docDir.path}/covers');
    if (!await coversDir.exists()) await coversDir.create(recursive: true);

    bool registryChanged = false;
    final ytm = ytmusic.YTMusic();
    bool ytmInitialized = false;

    // Usamos toList() para iterar sobre una copia segura
    for (var song in songs.toList()) {
      final meta = simulatedMetadata[song.data];
      String? artworkUrl = meta?['artworkUrl']?.toString();
      final needsArtistFix = _isUnknownArtist(meta?['artist'] as String?);

      bool needsArtworkSync;
      if (artworkUrl == null) {
        // Sin portada asignada todavía: hay que buscarla.
        needsArtworkSync = true;
      } else if (artworkUrl.startsWith('http')) {
        needsArtworkSync = true;
      } else if (artworkUrl.startsWith('file://')) {
        final localFile = File(artworkUrl.replaceFirst('file://', ''));
        // Si no existe o pesa menos de 40KB, es casi seguro que es baja resolución (o falta).
        needsArtworkSync = !localFile.existsSync() || localFile.lengthSync() < 40000;
      } else {
        needsArtworkSync = false;
      }

      if (!needsArtworkSync && !needsArtistFix) continue;

      Uint8List? hdArtworkBytes;
      String? correctedArtist;
      String? correctedTitle;

      // 1. Primero buscar una portada ya embebida en el archivo (MediaStore/ID3),
      // es gratis e instantáneo comparado con salir a buscar a YouTube.
      if (needsArtworkSync) {
        try {
          Uint8List? localBytes = await audioQuery.queryArtwork(song.id, ArtworkType.AUDIO);
          if (localBytes == null || localBytes.isEmpty) {
            try {
              final tag = await AudioTags.read(song.data);
              if (tag != null && tag.pictures.isNotEmpty) {
                localBytes = tag.pictures.first.bytes;
              }
            } catch (e) {
              print("Error reading ID3 directly: $e");
            }
          }
          if (localBytes != null && localBytes.isNotEmpty) {
            hdArtworkBytes = localBytes;
          }
        } catch (e) {
          print("Error checking local artwork: $e");
        }
      }

      // 2. Si falta portada local o el artista sigue sin identificarse, buscar en
      // YouTube Music: esto permite corregir artista/título aunque la portada ya esté bien.
      if (hdArtworkBytes == null || needsArtistFix) {
        try {
          if (!ytmInitialized) {
            await ytm.initialize();
            ytmInitialized = true;
          }

          final artist = (meta?['artist'] as String?) ?? '';
          final title = (meta?['title'] as String?) ?? song.title;

          String query = title;
          if (!_isUnknownArtist(artist)) {
            query = "$artist $title";
          }

          final results = await ytm.search(query);
          final songResult = results.whereType<ytmusic.SongDetailed>().firstOrNull;

          if (songResult != null) {
            if (needsArtistFix) {
              correctedArtist = songResult.artist.name;
              correctedTitle = songResult.name;
            }

            if (hdArtworkBytes == null && songResult.thumbnails.isNotEmpty) {
              final rawUrl = songResult.thumbnails.last.url;
              final hdUrl = rawUrl.replaceFirst(RegExp(r'=w\d+-h\d+.*'), '=w1080-h1080');

              final dio = dio_pkg.Dio();
              final res = await dio.get<List<int>>(
                hdUrl,
                options: dio_pkg.Options(responseType: dio_pkg.ResponseType.bytes),
              );

              if (res.data != null) {
                hdArtworkBytes = Uint8List.fromList(res.data!);
              }
            }
          }
        } catch (e) {
          print("Error buscando en YouTube Music para ${song.title}: $e");
        }
      }

      if (hdArtworkBytes == null && correctedArtist == null) continue;

      simulatedMetadata[song.data] = simulatedMetadata[song.data] ?? {};
      final songMeta = simulatedMetadata[song.data]!;

      if (correctedArtist != null) {
        songMeta['artist'] = correctedArtist;
        songMeta['title'] = correctedTitle;
        registryChanged = true;
      }

      // 3. Guardar la portada físicamente (si se encontró una nueva)
      if (hdArtworkBytes != null) {
        final safeTitle = (songMeta['title']?.toString() ?? song.data.split('/').last).replaceAll(RegExp(r'[\\/*?:"<>|]'), "");
        final artFile = File('${coversDir.path}/$safeTitle.jpg');
        await artFile.writeAsBytes(hdArtworkBytes);

        songMeta['artworkUrl'] = 'file://${artFile.path}';
        registryChanged = true;

        // Inyectar en ID3 la versión HD (con el artista/título ya corregidos)
        try {
           final newTag = Tag(
             title: songMeta['title'],
             trackArtist: songMeta['artist'],
             pictures: [
               Picture(
                 bytes: hdArtworkBytes,
                 mimeType: MimeType.jpeg,
                 pictureType: PictureType.coverFront,
               )
             ]
           );
           await AudioTags.write(song.data, newTag);
        } catch (_) {}
      }
    }

    if (registryChanged) {
      final file = File('${docDir.path}/metadata_registry.json');
      await file.writeAsString(jsonEncode(simulatedMetadata));
      notifyListeners();
      print("Sincronización de portadas offline y actualización HD completada.");
    }
  }

  Future<void> hideSong(String path) async {
    if (!hiddenSongs.contains(path)) {
      hiddenSongs.add(path);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('hidden_songs', hiddenSongs);
      } catch (e) {
        print("Error saving hidden songs: $e");
      }
      songs.removeWhere((s) => s.data == path);
      notifyListeners();
    }
  }

  Future<void> unhideSong(String path) async {
    if (hiddenSongs.contains(path)) {
      hiddenSongs.remove(path);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('hidden_songs', hiddenSongs);
      } catch (e) {
        print("Error saving hidden songs: $e");
      }
      // Reload songs to ensure the unhidden song is back in the library
      await loadSongs();
    }
  }

  Future<void> deleteSong(String path) async {
    // Remove from the active queue/playlist first so playback doesn't reference a missing file.
    final queueIndex = queue.indexWhere((s) => s.data == path);
    if (queueIndex != -1) {
      removeFromQueue(queueIndex);
    }

    songs.removeWhere((s) => s.data == path);

    // Always keep the path excluded from future loadSongs() calls. This is a safety net:
    // on Android 10+ (scoped storage) direct File.delete() can silently fail for media
    // not owned by the app, and even when it succeeds, MediaStore may keep a stale row
    // until re-scanned, so without this the "deleted" song reappears after reload.
    // Uses its own list (not hiddenSongs) so a deleted song never shows up under
    // "Canciones ocultas" — eliminar y ocultar son acciones distintas.
    if (!deletedSongs.contains(path)) {
      deletedSongs.add(path);
    }
    // Por si la canción estaba oculta antes de eliminarla, sacarla de esa lista también.
    hiddenSongs.remove(path);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('deleted_songs', deletedSongs);
      await prefs.setStringList('hidden_songs', hiddenSongs);
    } catch (e) {
      print("Error updating deleted/hidden songs: $e");
    }

    if (simulatedMetadata.remove(path) != null) {
      try {
        final docDir = await getApplicationDocumentsDirectory();
        final file = File('${docDir.path}/metadata_registry.json');
        await file.writeAsString(jsonEncode(simulatedMetadata));
      } catch (e) {
        print("Error updating metadata registry: $e");
      }
    }

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        // Notify MediaStore so it drops the row for the deleted file; otherwise
        // querySongs() keeps returning it (see on_audio_query's scanMedia docs).
        await audioQuery.scanMedia(path);
      }
    } catch (e) {
      print("Error deleting song file: $e");
    }

    notifyListeners();
  }

  Future<List<SongModel>> getHiddenSongModels() async {
    if (hiddenSongs.isEmpty) return [];
    final allSongs = await audioQuery.querySongs(
      sortType: null,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    return allSongs.where((song) => hiddenSongs.contains(song.data)).toList();
  }

  Future<void> playSong(int index) async {
    if (index < 0 || index >= songs.length) return;
    await playQueue(songs, index);
  }

  Future<void> playQueue(
    List<SongModel> newQueue,
    int startIndex, {
    bool autoPlay = true,
  }) async {
    if (startIndex < 0 || startIndex >= newQueue.length) return;

    queue = List.from(newQueue);
    currentIndex = startIndex;

    final audioSources = queue.map((song) => _createAudioSource(song)).toList();
    _playlist = ConcatenatingAudioSource(children: audioSources);

    try {
      await audioPlayer.setAudioSource(
        _playlist,
        initialIndex: startIndex,
        initialPosition: Duration.zero,
      );
      if (autoPlay) {
        audioPlayer.play();
      }
      notifyListeners();
    } catch (e) {
      print("Error playing queue: $e");
    }
  }

  AudioSource _createAudioSource(SongModel song) {
    final songPath = song.data;
    final metadata = simulatedMetadata[songPath];
    final title = metadata?['title'] ?? song.title;
    final artist = metadata?['artist'] ?? song.artist ?? "Desconocido";
    final rawArtworkUrl = metadata?['artworkUrl'];
    final artworkUri = rawArtworkUrl != null
        ? Uri.parse(
            rawArtworkUrl.toString().replaceFirst(
              RegExp(r'=w\d+-h\d+'),
              '=w1080-h1080',
            ),
          )
        : null;

    return AudioSource.uri(
      Uri.file(songPath),
      tag: MediaItem(
        id: songPath,
        album: artist,
        title: title,
        artist: artist,
        artUri: artworkUri,
      ),
    );
  }

  void playNext() {
    if (audioPlayer.hasNext) {
      audioPlayer.seekToNext();
    } else if (queue.isNotEmpty) {
      audioPlayer.seek(Duration.zero, index: 0);
    }
  }

  void playPrevious() {
    if (audioPlayer.hasPrevious) {
      audioPlayer.seekToPrevious();
    } else if (queue.isNotEmpty) {
      audioPlayer.seek(Duration.zero, index: queue.length - 1);
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = queue.removeAt(oldIndex);
    queue.insert(newIndex, item);

    // Move in ConcatenatingAudioSource to keep native queue in sync
    _playlist.move(oldIndex, newIndex);

    if (currentIndex == oldIndex) {
      currentIndex = newIndex;
    } else if (currentIndex > oldIndex && currentIndex <= newIndex) {
      currentIndex--;
    } else if (currentIndex < oldIndex && currentIndex >= newIndex) {
      currentIndex++;
    }
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= queue.length) return;

    queue.removeAt(index);
    _playlist.removeAt(index);

    if (currentIndex > index) {
      currentIndex--;
    }
    // If the removed item was the currently playing one, just_audio automatically skips to the next source!
    notifyListeners();
  }

  /// Reproduce una URL o archivo local suelto (ej. vista previa de una
  /// búsqueda en Explorar) usando el único AudioPlayer de la app. Guarda el
  /// estado de la cola real la primera vez que se llama, para poder
  /// restaurarlo con [stopExternalPreview].
  Future<void> playExternalPreview(
    String source, {
    String title = 'Vista previa',
    String? artist,
    bool isLocalFile = false,
  }) async {
    if (!_isPreviewingExternal) {
      _previewWasPlaying = audioPlayer.playing;
      _previewSavedPosition = queue.isNotEmpty ? audioPlayer.position : null;
    }
    _isPreviewingExternal = true;
    try {
      final uri = isLocalFile ? Uri.file(source) : Uri.parse(source);
      // just_audio_background exige que todo AudioSource tenga un MediaItem
      // como tag, o falla el assert al setearlo.
      await audioPlayer.setAudioSource(AudioSource.uri(
        uri,
        tag: MediaItem(id: source, title: title, artist: artist),
      ));
      await audioPlayer.play();
    } catch (e) {
      _isPreviewingExternal = false;
      rethrow;
    }
  }

  /// Detiene la vista previa y restaura la cola real (canción y posición)
  /// que estaba sonando antes de empezar a previsualizar, si había alguna.
  Future<void> stopExternalPreview() async {
    if (!_isPreviewingExternal) return;
    _isPreviewingExternal = false;
    try {
      await audioPlayer.stop();
      if (queue.isNotEmpty) {
        final restoreIndex = currentIndex.clamp(0, queue.length - 1);
        await audioPlayer.setAudioSource(
          _playlist,
          initialIndex: restoreIndex,
          initialPosition: _previewSavedPosition ?? Duration.zero,
        );
        if (_previewWasPlaying) {
          await audioPlayer.play();
        }
      }
    } catch (e) {
      print("Error restaurando reproducción tras la vista previa: $e");
    }
  }

  void togglePlayPause() {
    if (audioPlayer.playing) {
      audioPlayer.pause();
    } else {
      audioPlayer.play();
    }
  }

  void toggleShuffle() {
    final enable = !audioPlayer.shuffleModeEnabled;
    audioPlayer.setShuffleModeEnabled(enable);
  }

  void toggleLoop() {
    final current = audioPlayer.loopMode;
    if (current == LoopMode.off) {
      audioPlayer.setLoopMode(LoopMode.all);
    } else if (current == LoopMode.all) {
      audioPlayer.setLoopMode(LoopMode.one);
    } else {
      audioPlayer.setLoopMode(LoopMode.off);
    }
  }
}
