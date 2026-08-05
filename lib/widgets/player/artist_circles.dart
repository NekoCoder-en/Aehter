import 'dart:io';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class ArtistCircles extends StatefulWidget {
  final String rawArtists;
  const ArtistCircles({Key? key, required this.rawArtists}) : super(key: key);

  @override
  State<ArtistCircles> createState() => _ArtistCirclesState();
}

class _ArtistCirclesState extends State<ArtistCircles> {
  static final Map<String, List<Map<String, String>>> _cache = {};
  Future<List<Map<String, String>>>? _profilesFuture;

  @override
  void initState() {
    super.initState();
    _profilesFuture = _fetchProfiles();
  }

  Future<List<Map<String, String>>> _fetchProfiles() async {
    if (_cache.containsKey(widget.rawArtists)) {
      return _cache[widget.rawArtists]!;
    }

    try {
      final result = await InternetAddress.lookup('youtube.com').timeout(const Duration(seconds: 3));
      if (result.isEmpty || result[0].rawAddress.isEmpty) return [];
      
      final yt = YoutubeExplode();
      final artistNames = widget.rawArtists.split(RegExp(r'[,&]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      List<Map<String, String>> profiles = [];
      
      for (var name in artistNames) {
        try {
          final searchResults = await yt.search.search(name);
          if (searchResults.isNotEmpty) {
            final video = searchResults.first;
            final channel = await yt.channels.get(video.channelId);
            profiles.add({'name': name, 'url': channel.logoUrl});
          }
        } catch (_) {
          // ignore error for a single artist
        }
      }
      yt.close();
      if (profiles.isNotEmpty) {
        _cache[widget.rawArtists] = profiles;
      }
      return profiles;
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, String>>>(
      future: _profilesFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final profiles = snapshot.data!;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: profiles.map((p) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundImage: NetworkImage(p['url']!),
                    backgroundColor: Colors.grey[800],
                  ),
                  const SizedBox(height: 8),
                  Text(p['name']!, style: const TextStyle(color: Colors.white, fontSize: 14)),
                ],
              ),
            )).toList(),
          ),
        );
      },
    );
  }
}
