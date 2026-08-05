import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class PlaylistManager extends ChangeNotifier {
  static final PlaylistManager _instance = PlaylistManager._internal();
  factory PlaylistManager() => _instance;
  PlaylistManager._internal();

  // Mapa de Name -> Lista de paths
  Map<String, List<String>> playlists = {
    'Favoritos': [],
  };

  Future<void> loadPlaylists() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/playlists.json');
      if (file.existsSync()) {
        final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        playlists.clear();
        data.forEach((key, value) {
          playlists[key] = List<String>.from(value);
        });
        
        if (!playlists.containsKey('Favoritos')) {
          playlists['Favoritos'] = [];
        }
      }
    } catch (e) {
      print("Error loading playlists: $e");
    }
    notifyListeners();
  }

  Future<void> _savePlaylists() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/playlists.json');
      file.writeAsStringSync(jsonEncode(playlists));
      notifyListeners();
    } catch (e) {
      print("Error saving playlists: $e");
    }
  }

  void createPlaylist(String name) {
    if (!playlists.containsKey(name)) {
      playlists[name] = [];
      _savePlaylists();
    }
  }

  void toggleFavorite(String path) {
    if (isFavorite(path)) {
      playlists['Favoritos']?.remove(path);
    } else {
      playlists['Favoritos']?.add(path);
    }
    _savePlaylists();
  }

  bool isFavorite(String path) {
    return playlists['Favoritos']?.contains(path) ?? false;
  }

  void addToPlaylist(String playlistName, String path) {
    if (playlists.containsKey(playlistName)) {
      if (!playlists[playlistName]!.contains(path)) {
        playlists[playlistName]!.add(path);
        _savePlaylists();
      }
    }
  }

  void removeFromPlaylist(String playlistName, String path) {
    if (playlists.containsKey(playlistName)) {
      playlists[playlistName]!.remove(path);
      _savePlaylists();
    }
  }
}
