import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart' as ytmusic;

class SyncedLyric {
  final String text;
  final Duration startTime;
  final Duration endTime;

  SyncedLyric({
    required this.text,
    required this.startTime,
    required this.endTime,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'startTime': startTime.inMilliseconds,
    'endTime': endTime.inMilliseconds,
  };

  factory SyncedLyric.fromJson(Map<String, dynamic> json) => SyncedLyric(
    text: json['text'] as String,
    startTime: Duration(milliseconds: json['startTime'] as int),
    endTime: Duration(milliseconds: json['endTime'] as int),
  );
}

class LyricsService {
  static final LyricsService _instance = LyricsService._internal();
  factory LyricsService() => _instance;
  LyricsService._internal();

  String _getSafeFilename(String id) {
    return base64UrlEncode(utf8.encode(id)).replaceAll('=', '');
  }

  Future<File> _getLyricsFile(String songPath) async {
    final dir = await getApplicationDocumentsDirectory();
    final lyricsDir = Directory('${dir.path}/lyrics');
    if (!await lyricsDir.exists()) {
      await lyricsDir.create(recursive: true);
    }
    final safeName = _getSafeFilename(songPath);
    return File('${lyricsDir.path}/$safeName.json');
  }

  Future<List<SyncedLyric>?> getLyrics(String songPath, String artist, String title, {bool forceRefresh = false}) async {
    try {
      final file = await _getLyricsFile(songPath);
      
      // 1. Check local cache (Offline mode)
      if (!forceRefresh && await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        return jsonList.map((e) => SyncedLyric.fromJson(e)).toList();
      }

      // 2. Not found locally, fetch from YT Music
      final ytm = ytmusic.YTMusic();
      await ytm.initialize();
      
      String cleanString(String input) {
        String s = input.replaceAll(RegExp(r'\(.*?(official|video|audio|lyric|en vivo|live).*?\)', caseSensitive: false), '');
        s = s.replaceAll(RegExp(r'\[.*?(official|video|audio|lyric|en vivo|live).*?\]', caseSensitive: false), '');
        s = s.replaceAll(' - Topic', '');
        s = s.replaceAll('Topic', '');
        s = s.replaceAll('VEVO', '');
        return s.trim();
      }

      String query = "";
      bool isUnknown(String? a) => a == null || a.toLowerCase() == 'unknown artist' || a.toLowerCase() == '<unknown>' || a.toLowerCase() == 'desconocido';
      
      String cleanArtist = cleanString(artist);
      final cleanTitle = cleanString(title);

      // Si el nombre del artista tiene un " - " (ej: Carre - Minina), probablamente contiene el título también
      if (cleanArtist.contains(' - ')) {
        cleanArtist = cleanArtist.split(' - ')[0].trim();
      }

      if (!isUnknown(cleanArtist)) {
        query += "$cleanArtist ";
      }
      query += cleanTitle;

      final results = await ytm.search(query);
      final songs = results.whereType<ytmusic.SongDetailed>().toList();
      
      ytmusic.SongDetailed? songResult;
      // Tratar de encontrar la canción que coincida con el título
      for (var song in songs) {
        final lowerName = song.name.toLowerCase();
        final lowerTitle = cleanTitle.toLowerCase();
        if (lowerName == lowerTitle || 
            lowerName.contains(lowerTitle) || 
            lowerTitle.contains(lowerName)) {
          songResult = song;
          break;
        }
      }
      
      // Si no hay match exacto, tomamos la primera por defecto
      if (songResult == null) {
        songResult = songs.firstOrNull;
      }
      
      if (songResult == null) {
        // Fallback a local si falla el internet
        if (await file.exists()) {
          final content = await file.readAsString();
          return (jsonDecode(content) as List).map((e) => SyncedLyric.fromJson(e)).toList();
        }
        return null;
      }

      final lyricsRes = await ytm.getTimedLyrics(songResult.videoId);
      if (lyricsRes == null || lyricsRes.timedLyricsData.isEmpty) {
        // Fallback a local si falla el internet
        if (await file.exists()) {
          final content = await file.readAsString();
          return (jsonDecode(content) as List).map((e) => SyncedLyric.fromJson(e)).toList();
        }
        return null;
      }

      final List<SyncedLyric> parsedLyrics = [];
      for (var data in lyricsRes.timedLyricsData) {
        if (data.lyricLine != null && data.cueRange != null) {
          parsedLyrics.add(SyncedLyric(
            text: data.lyricLine!,
            startTime: Duration(milliseconds: data.cueRange!.startTimeMilliseconds),
            endTime: Duration(milliseconds: data.cueRange!.endTimeMilliseconds),
          ));
        }
      }

      // 3. Save to local cache
      if (parsedLyrics.isNotEmpty) {
        await file.writeAsString(jsonEncode(parsedLyrics.map((e) => e.toJson()).toList()));
      }

      return parsedLyrics;
    } catch (e) {
      print("Error fetching lyrics: $e");
      return null;
    }
  }

  Future<void> prefetchLyrics(String songPath, String artist, String title) async {
    final file = await _getLyricsFile(songPath);
    if (!await file.exists()) {
      await getLyrics(songPath, artist, title);
    }
  }

  Future<void> saveCustomLyrics(String songPath, List<SyncedLyric> lyrics) async {
    final file = await _getLyricsFile(songPath);
    await file.writeAsString(jsonEncode(lyrics.map((e) => e.toJson()).toList()));
  }
}
