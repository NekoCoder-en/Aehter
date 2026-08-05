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
      if (index != null && index >= 0 && index < queue.length) {
        currentIndex = index;

        // Lazy load artwork for the current song
        final songPath = queue[currentIndex].data;
        _tryRecoverArtwork(songPath, queue[currentIndex].id);

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
  int currentIndex = -1;

  SongModel? get currentSong => currentIndex >= 0 && currentIndex < queue.length
      ? queue[currentIndex]
      : null;

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
    } catch (e) {
      print("Error loading hidden songs: $e");
    }

    songs = allSongs.where((song) {
      final title = song.title.toUpperCase();
      final fileName = song.data.toUpperCase();

      if (title.startsWith('AUD-') || fileName.contains('AUD-')) return false;
      if (title.contains('-WA') || fileName.contains('-WA')) return false;
      if (hiddenSongs.contains(song.data)) return false;

      return true;
    }).toList();

    // Generar o arreglar metadatos simulados para canciones viejas
    for (var song in songs) {
      bool isUnknown(String? a) =>
          a == null ||
          a == "Unknown Artist" ||
          a == "<unknown>" ||
          a == "Desconocido" ||
          a.isEmpty;

      final meta = simulatedMetadata[song.data];
      if (meta == null || isUnknown(meta['artist'] as String?)) {
        final filename = song.data
            .split('/')
            .last
            .replaceAll(RegExp(r'\.mp3|\.m4a'), '');
        String artist = song.artist ?? "Unknown Artist";
        if (isUnknown(artist)) artist = "Unknown Artist";
        String parsedTitle = song.title;

        if (isUnknown(artist)) {
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

    // Iniciar sincronización silenciosa de portadas para que funcionen offline
    _syncMissingCoversInBackground();
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

      bool needsHDSync = false;
      Uint8List? hdArtworkBytes;

      if (artworkUrl != null && artworkUrl.startsWith('http')) {
        needsHDSync = true;
      } else if (artworkUrl != null && artworkUrl.startsWith('file://')) {
        final localFile = File(artworkUrl.replaceFirst('file://', ''));
        if (localFile.existsSync() && localFile.lengthSync() < 40000) {
          // Si pesa menos de 40KB, es casi seguro que es baja resolución.
          needsHDSync = true;
        }
      }

      if (needsHDSync) {
        try {
          if (!ytmInitialized) {
            await ytm.initialize();
            ytmInitialized = true;
          }

          final artist = meta?['artist'] ?? '';
          final title = meta?['title'] ?? song.title;
          
          String query = title;
          if (artist.toLowerCase() != 'unknown artist' && artist.toLowerCase() != '<unknown>' && artist != 'Desconocido') {
            query = "$artist $title";
          }

          final results = await ytm.search(query);
          final songResult = results.whereType<ytmusic.SongDetailed>().firstOrNull;

          if (songResult != null && songResult.thumbnails.isNotEmpty) {
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
        } catch (e) {
          print("Error fetching HD cover for ${song.title}: $e");
        }

        // 3. Guardar físicamente
        if (hdArtworkBytes != null) {
          final safeTitle = (meta?['title']?.toString() ?? song.data.split('/').last).replaceAll(RegExp(r'[\\/*?:"<>|]'), "");
          final artFile = File('${coversDir.path}/$safeTitle.jpg');
          await artFile.writeAsBytes(hdArtworkBytes);
          
          simulatedMetadata[song.data]!['artworkUrl'] = 'file://${artFile.path}';
          registryChanged = true;
          
          // Inyectar en ID3 la versión HD
          try {
             final newTag = Tag(
               title: meta?['title'],
               trackArtist: meta?['artist'],
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

  Future<void> _tryRecoverArtwork(String songPath, int songId) async {
    final meta = simulatedMetadata[songPath];
    if (meta == null) return;

    bool isUnknown(String? a) =>
        a == null ||
        a.toLowerCase() == 'unknown artist' ||
        a.toLowerCase() == '<unknown>' ||
        a.toLowerCase() == 'desconocido';
    final needsArtistFix = isUnknown(meta['artist'] as String?);

    final artworkUrl = meta['artworkUrl']?.toString();
    final isLowResYoutubeThumb =
        artworkUrl != null && artworkUrl.contains('i.ytimg.com/vi/');

    // Si ya tiene foto HD (o local) Y el artista ESTÁ BIEN, no hacemos nada.
    if (!needsArtistFix && artworkUrl != null && !isLowResYoutubeThumb) return;

    // Si la canción YA tiene una portada local integrada, NO buscar en YouTube
    try {
      Uint8List? artworkBytes = await audioQuery.queryArtwork(
        songId,
        ArtworkType.AUDIO,
      );

      // Si MediaStore no la encontró, intentamos leer las etiquetas ID3 directamente
      if (artworkBytes == null || artworkBytes.isEmpty) {
        try {
          final tag = await AudioTags.read(songPath);
          if (tag != null && tag.pictures.isNotEmpty) {
            artworkBytes = tag.pictures.first.bytes;
          }
        } catch (e) {
          print("Error reading ID3 directly: $e");
        }
      }

      if (artworkBytes != null && artworkBytes.isNotEmpty) {
        // Guardarla permanentemente en covers/
        final docDir = await getApplicationDocumentsDirectory();
        final coversDir = Directory('${docDir.path}/covers');
        if (!await coversDir.exists()) await coversDir.create(recursive: true);

        final safeTitle = (meta['title'] ?? songPath.split('/').last).replaceAll(RegExp(r'[\\/*?:"<>|]'), "");
        final artFile = File('${coversDir.path}/$safeTitle.jpg');
        
        if (!artFile.existsSync()) {
          await artFile.writeAsBytes(artworkBytes);
        }
        
        simulatedMetadata[songPath] = simulatedMetadata[songPath] ?? {};
        simulatedMetadata[songPath]!['artworkUrl'] = 'file://${artFile.path}';

        // Guardar permanentemente
        final registryFile = File('${docDir.path}/metadata_registry.json');
        await registryFile.writeAsString(jsonEncode(simulatedMetadata));

        // Refrescar el queue nativo
        final index = queue.indexWhere((s) => s.data == songPath);
        if (index != -1 && index < _playlist.length) {
          await _playlist.removeAt(index);
          await _playlist.insert(index, _createAudioSource(queue[index]));
        }
        notifyListeners();
        return; // Ya tiene foto real, no hacer nada más
      }
    } catch (e) {
      print("Error checking local artwork: $e");
    }

    try {
      final ytm = ytmusic.YTMusic();
      await ytm.initialize();

      final artist = meta['artist'] ?? '';
      final title = meta['title'] ?? '';

      String query = "";
      if (artist.toLowerCase() != 'unknown artist' &&
          artist.toLowerCase() != '<unknown>') {
        query += "$artist ";
      }
      query += title;

      final results = await ytm.search(query);
      final songResult = results.whereType<ytmusic.SongDetailed>().firstOrNull;

      if (songResult != null && songResult.thumbnails.isNotEmpty) {
        final hdArtwork = songResult.thumbnails.last.url;
        simulatedMetadata[songPath]!['artworkUrl'] = hdArtwork;

        // Siempre actualizamos el título y artista con los oficiales de YT Music
        // porque son mucho más precisos que los que adivinamos del nombre del archivo.
        simulatedMetadata[songPath]!['artist'] = songResult.artist.name;
        simulatedMetadata[songPath]!['title'] = songResult.name;

        // Inyectar los metadatos físicos en el archivo (ID3)
        try {
          final dio = dio_pkg.Dio();
          final res = await dio.get<List<int>>(
            hdArtwork,
            options: dio_pkg.Options(responseType: dio_pkg.ResponseType.bytes),
          );

          final finalTitle = simulatedMetadata[songPath]!['title'] as String;
          final finalArtist = simulatedMetadata[songPath]!['artist'] as String;

          final tag = Tag(
            title: finalTitle,
            trackArtist: finalArtist,
            pictures: res.data != null
                ? [
                    Picture(
                      bytes: Uint8List.fromList(res.data!),
                      mimeType: MimeType.jpeg,
                      pictureType: PictureType.coverFront,
                    ),
                  ]
                : [],
          );
          await AudioTags.write(songPath, tag);
          print("ID3 tags injected into old file successfully!");
        } catch (e) {
          print("Error inyectando ID3 en recovery: $e");
        }

        // Actualizar el item en la lista de reproducción nativa si es posible
        final index = queue.indexWhere((s) => s.data == songPath);
        if (index != -1 && index < _playlist.length) {
          // Re-create the source with the new artwork to update the notification
          await _playlist.removeAt(index);
          await _playlist.insert(index, _createAudioSource(queue[index]));
        }

        notifyListeners();

        // Guardar el registro permanentemente
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/metadata_registry.json');
        await file.writeAsString(jsonEncode(simulatedMetadata));
      }
    } catch (e) {
      print("Error recuperando portada de YouTube: $e");
    }
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
