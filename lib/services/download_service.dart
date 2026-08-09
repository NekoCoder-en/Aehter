import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audiotags/audiotags.dart';
import 'package:screen_recorder/services/lyrics_service.dart';

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 90),
      receiveTimeout: const Duration(seconds: 120),
    ),
  );

  final OnAudioQuery _audioQuery = OnAudioQuery();
  final YoutubeExplode _yt = YoutubeExplode();

  // Guarda metadatos simulados para mostrarlos en la UI
  Future<void> _saveSimulatedMetadata(String filePath, String artist, String title, String? artworkUrl) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/metadata_registry.json');
      Map<String, dynamic> registry = {};
      if (file.existsSync()) {
        registry = jsonDecode(file.readAsStringSync());
      }
      registry[filePath] = {
        'artist': artist,
        'title': title,
        'artworkUrl': artworkUrl,
      };
      file.writeAsStringSync(jsonEncode(registry));
    } catch (e) {
      print("Error guardando metadatos simulados: $e");
    }
  }

  Future<String?> downloadAudio(
      String videoId, String title, String? artworkUrl, String? artistName, Function(int, int) onProgress) async {
    try {
      print("Starting download for: $title");
      if (!await _requestPermissions()) {
        print("Permissions denied");
        return null;
      }
      print("Permissions granted");

      final finalSavePath = await _getDownloadPath(title);
      if (finalSavePath == null) {
        print("Could not get save path");
        return null;
      }

      print("Getting manifest...");
      var manifest = await _yt.videos.streamsClient.getManifest(videoId);
      var streamInfo = manifest.muxed.withHighestBitrate();
      print("Stream info obtained. Size: ${streamInfo.size.totalBytes}");

      var stream = _yt.videos.streamsClient.get(streamInfo);
      var file = File(finalSavePath);
      var fileStream = file.openWrite();
      
      var totalSize = streamInfo.size.totalBytes;
      int downloaded = 0;

      print("Starting stream listener...");
      await for (final data in stream) {
        downloaded += data.length;
        onProgress(downloaded, totalSize);
        fileStream.add(data);
      }
      print("Stream finished. Flushing file...");
      await fileStream.flush();
      await fileStream.close();

      // Preparar etiquetas ID3 para inyectar al archivo
      String artist = artistName ?? "Unknown Artist";
      String songTitle = title;
      
      if (title.contains(" - ")) {
        final parts = title.split(" - ");
        artist = parts[0].trim();
        songTitle = parts.sublist(1).join(" - ").trim();
      }

      // Descargar la portada HD para inyectarla en el archivo
      List<int>? artworkBytes;
      String? localArtworkPath;
      if (artworkUrl != null) {
        try {
          final hdArtworkUrl = artworkUrl.replaceFirst(RegExp(r'=w\d+-h\d+.*'), '=w1080-h1080');
          final res = await _dio.get<List<int>>(
            hdArtworkUrl,
            options: Options(responseType: ResponseType.bytes),
          );
          artworkBytes = res.data;
          
          if (artworkBytes != null) {
            // Guardar la foto físicamente en una carpeta oculta
            final docDir = await getApplicationDocumentsDirectory();
            final coversDir = Directory('${docDir.path}/covers');
            if (!await coversDir.exists()) await coversDir.create(recursive: true);
            
            final safeTitle = title.replaceAll(RegExp(r'[\\/*?:"<>|]'), "");
            final coverFile = File('${coversDir.path}/$safeTitle.jpg');
            await coverFile.writeAsBytes(artworkBytes);
            localArtworkPath = 'file://${coverFile.path}';
          }
        } catch (e) {
          print("Error downloading artwork for ID3: $e");
        }
      }

      // Escribir las etiquetas físicas en el archivo
      try {
        final tag = Tag(
          title: songTitle,
          trackArtist: artist,
          pictures: artworkBytes != null ? [
            Picture(
              bytes: Uint8List.fromList(artworkBytes),
              mimeType: MimeType.jpeg,
              pictureType: PictureType.coverFront,
            )
          ] : [],
        );
        await AudioTags.write(finalSavePath, tag);
        print("ID3 tags injected successfully!");
      } catch (e) {
        print("Error injecting ID3 tags: $e");
      }

      // Opcional: seguir guardando la simulación por compatibilidad antigua
      // Guardar el link LOCAL en lugar del link web para asegurar que funcione sin internet
      await _saveSimulatedMetadata(finalSavePath, artist, songTitle, localArtworkPath ?? artworkUrl);

      // Descargar las letras en segundo plano para tenerlas offline
      LyricsService().prefetchLyrics(finalSavePath, artist, songTitle).catchError((e) {
        print("Error prefetching lyrics: $e");
      });

      // Request system to scan
      try {
        await _audioQuery.scanMedia(finalSavePath);
      } catch (e) {
        print("Error scanning media: $e");
      }

      print("Download completed successfully.");
      return finalSavePath;
    } catch (e, stacktrace) {
      print("Download error: $e");
      print(stacktrace);
      return null;
    }
  }

  Future<String?> downloadVideo(
      String videoId, String title, Function(int, int) onProgress, {int? itag}) async {
    try {
      print("Starting video download for: $title");
      if (!await _requestPermissions()) {
        print("Permissions denied");
        return null;
      }

      final finalSavePath = await _getVideoDownloadPath(title);
      if (finalSavePath == null) {
        print("Could not get save path");
        return null;
      }

      var manifest = await _yt.videos.streamsClient.getManifest(videoId);
      // Stream muxed (video+audio en un solo archivo reproducible), no
      // requiere unir pistas por separado. Si se pidió una calidad
      // específica (itag) la buscamos; si no está más disponible, caemos
      // a la de mayor bitrate.
      final muxedStreams = manifest.muxed.toList();
      var streamInfo = itag != null
          ? muxedStreams.where((s) => s.tag == itag).firstOrNull ?? manifest.muxed.withHighestBitrate()
          : manifest.muxed.withHighestBitrate();

      var stream = _yt.videos.streamsClient.get(streamInfo);
      var file = File(finalSavePath);
      var fileStream = file.openWrite();

      var totalSize = streamInfo.size.totalBytes;
      int downloaded = 0;

      await for (final data in stream) {
        downloaded += data.length;
        onProgress(downloaded, totalSize);
        fileStream.add(data);
      }
      await fileStream.flush();
      await fileStream.close();

      // Pedirle al sistema que indexe el nuevo archivo. scanMedia() está
      // pensado para audio (on_audio_query) y con un video puede quedarse
      // colgado sin resolver nunca — como el archivo ya se guardó bien y la
      // pestaña Videos escanea la carpeta directamente (no depende de
      // MediaStore), esto es solo un "nice to have": con timeout para que
      // nunca trabe la descarga.
      try {
        await _audioQuery.scanMedia(finalSavePath).timeout(const Duration(seconds: 5));
      } catch (e) {
        print("Error scanning video media (non-blocking): $e");
      }

      print("Video download completed successfully.");
      return finalSavePath;
    } catch (e, stacktrace) {
      print("Video download error: $e");
      print(stacktrace);
      return null;
    }
  }

  Future<String?> _getVideoDownloadPath(String title) async {
    Directory? directory;
    if (Platform.isAndroid) {
      // IMPORTANTE: tiene que ser "Movies", no "Music". El almacenamiento con
      // alcance limitado de Android rechaza (EPERM) crear un archivo de video
      // dentro de la colección "Music", que solo acepta audio.
      directory = Directory('/storage/emulated/0/Movies');
      if (!await directory.exists()) {
        try {
          await directory.create(recursive: true);
        } catch (_) {
          directory = await getExternalStorageDirectory();
        }
      }
    } else {
      directory = await getApplicationDocumentsDirectory();
    }

    if (directory == null) return null;

    // Misma carpeta "AppRec" que ya escanea la pestaña Videos de Biblioteca
    // (dentro de "Movies", que sí escanea de forma recursiva).
    final customDir = Directory('${directory.path}/AppRec');
    if (!await customDir.exists()) {
      await customDir.create(recursive: true);
    }

    final cleanTitle = title.replaceAll(RegExp(r'[\\/*?:"<>|]'), "");
    return '${customDir.path}/$cleanTitle.mp4';
  }

  Future<bool> _requestPermissions() async {
    final status = await Permission.storage.request();
    if (status.isGranted) return true;

    final audioStatus = await Permission.audio.request();
    return audioStatus.isGranted;
  }

  Future<String?> _getDownloadPath(String title) async {
    Directory? directory;
    if (Platform.isAndroid) {
      directory = Directory('/storage/emulated/0/Music');
      if (!await directory.exists()) {
        directory = await getExternalStorageDirectory();
      }
    } else {
      directory = await getApplicationDocumentsDirectory();
    }

    if (directory == null) return null;

    final customDir = Directory('${directory.path}/AppRec');
    if (!await customDir.exists()) {
      await customDir.create(recursive: true);
    }

    // Clean title for file name
    final cleanTitle = title.replaceAll(RegExp(r'[\\/*?:"<>|]'), "");
    return '${customDir.path}/$cleanTitle.mp3';
  }
}
