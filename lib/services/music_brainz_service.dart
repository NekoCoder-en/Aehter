import 'package:dio/dio.dart';

class MusicBrainzAlbum {
  final String id;
  final String title;
  final String? artist;
  final String? releaseDate;

  MusicBrainzAlbum({
    required this.id,
    required this.title,
    this.artist,
    this.releaseDate,
  });

  factory MusicBrainzAlbum.fromJson(Map<String, dynamic> json) {
    String? artistName;
    if (json['artist-credit'] != null && (json['artist-credit'] as List).isNotEmpty) {
      artistName = json['artist-credit'][0]['name'];
    }

    return MusicBrainzAlbum(
      id: json['id'],
      title: json['title'],
      artist: artistName,
      releaseDate: json['first-release-date'],
    );
  }
}

class MusicBrainzTrack {
  final String id;
  final String title;
  final String artist;

  MusicBrainzTrack({
    required this.id,
    required this.title,
    required this.artist,
  });
}

class MusicBrainzService {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://musicbrainz.org/ws/2',
      headers: {
        // MusicBrainz requires a descriptive User-Agent
        'User-Agent': 'FastMusicFlutterApp/1.0.0 (tu_email@example.com)',
        'Accept': 'application/json',
      },
    ),
  );

  Future<List<MusicBrainzAlbum>> searchAlbums(String query) async {
    try {
      // Se busca como frase literal (comillas) para que caracteres especiales
      // de la sintaxis Lucene de MusicBrainz (:, (), ", etc.) en la búsqueda
      // del usuario no rompan la consulta.
      final safeQuery = query.replaceAll('"', '');
      final response = await _dio.get(
        '/release-group',
        queryParameters: {
          'query': 'release-group:"$safeQuery" OR release:"$safeQuery"',
          'fmt': 'json',
          'limit': 20,
        },
      );

      final List groups = response.data['release-groups'] ?? [];
      return groups.map((g) => MusicBrainzAlbum.fromJson(g)).toList();
    } catch (e) {
      print("MusicBrainz Search Error: $e");
      return [];
    }
  }

  Future<List<MusicBrainzTrack>> getAlbumTracks(String releaseGroupId, String albumArtist) async {
    try {
      // Primero obtener la release principal (versión específica del álbum)
      final releaseResponse = await _dio.get(
        '/release-group/$releaseGroupId',
        queryParameters: {
          'inc': 'releases',
          'fmt': 'json',
        },
      );

      final releases = releaseResponse.data['releases'] as List?;
      if (releases == null || releases.isEmpty) return [];
      
      final mainReleaseId = releases.first['id'];

      // Ahora obtener las canciones de esa release
      final tracksResponse = await _dio.get(
        '/release/$mainReleaseId',
        queryParameters: {
          'inc': 'recordings',
          'fmt': 'json',
        },
      );

      final media = tracksResponse.data['media'] as List?;
      if (media == null || media.isEmpty) return [];

      final tracks = media.first['tracks'] as List?;
      if (tracks == null || tracks.isEmpty) return [];

      return tracks.map((t) {
        final recording = t['recording'];
        return MusicBrainzTrack(
          id: recording['id'],
          title: recording['title'],
          artist: albumArtist,
        );
      }).toList();
    } catch (e) {
      print("MusicBrainz Tracks Error: $e");
      return [];
    }
  }
}
