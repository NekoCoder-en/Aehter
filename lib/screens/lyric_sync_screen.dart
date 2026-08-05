import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_manager.dart';
import '../services/lyrics_service.dart';
import '../theme/app_colors.dart';

class LyricSyncScreen extends StatefulWidget {
  final String songPath;
  final String artist;
  final String title;

  const LyricSyncScreen({
    super.key,
    required this.songPath,
    required this.artist,
    required this.title,
  });

  @override
  State<LyricSyncScreen> createState() => _LyricSyncScreenState();
}

class _LyricSyncScreenState extends State<LyricSyncScreen> {
  int _step = 1;
  final TextEditingController _textController = TextEditingController();
  List<String> _rawLines = [];
  List<GlobalKey> _keys = [];
  final List<SyncedLyric> _syncedLyrics = [];
  int _currentIndex = 0;
  
  late AudioManager _audioManager;
  StreamSubscription? _positionSub;
  Duration _currentPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioManager = Provider.of<AudioManager>(context, listen: false);
    _positionSub = _audioManager.audioPlayer.positionStream.listen((pos) {
      if (mounted) setState(() => _currentPosition = pos);
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _textController.dispose();
    super.dispose();
  }

  void _goToStep2() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    
    _rawLines = text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (_rawLines.isEmpty) return;
    
    _keys = List.generate(_rawLines.length, (_) => GlobalKey());
    
    setState(() {
      _step = 2;
      _currentIndex = 0;
      _syncedLyrics.clear();
    });
    
    _audioManager.audioPlayer.seek(Duration.zero);
    _audioManager.audioPlayer.play();
  }

  void _syncNextLine() {
    if (_currentIndex >= _rawLines.length) return;
    
    if (_syncedLyrics.isNotEmpty) {
      final prev = _syncedLyrics.last;
      _syncedLyrics.removeLast();
      _syncedLyrics.add(SyncedLyric(
        text: prev.text,
        startTime: prev.startTime,
        endTime: _currentPosition,
      ));
    }
    
    _syncedLyrics.add(SyncedLyric(
      text: _rawLines[_currentIndex],
      startTime: _currentPosition,
      endTime: _currentPosition + const Duration(seconds: 5),
    ));
    
    setState(() {
      _currentIndex++;
    });
    
    if (_currentIndex < _keys.length && _keys[_currentIndex].currentContext != null) {
      Scrollable.ensureVisible(
        _keys[_currentIndex].currentContext!,
        duration: const Duration(milliseconds: 300),
        alignment: 0.5,
      );
    }
  }

  void _undoLine() {
    if (_currentIndex == 0) return;
    setState(() {
      _currentIndex--;
      _syncedLyrics.removeLast();
    });
    if (_syncedLyrics.isNotEmpty) {
       // Optionally seek back a few seconds
       _audioManager.audioPlayer.seek(_syncedLyrics.last.startTime - const Duration(seconds: 2));
    }
    
    if (_keys[_currentIndex].currentContext != null) {
      Scrollable.ensureVisible(
        _keys[_currentIndex].currentContext!,
        duration: const Duration(milliseconds: 300),
        alignment: 0.5,
      );
    }
  }

  Future<void> _finishAndSave() async {
    if (_syncedLyrics.isNotEmpty) {
      final prev = _syncedLyrics.last;
      _syncedLyrics.removeLast();
      _syncedLyrics.add(SyncedLyric(
        text: prev.text,
        startTime: prev.startTime,
        endTime: _currentPosition + const Duration(seconds: 10),
      ));
      
      await LyricsService().saveCustomLyrics(widget.songPath, _syncedLyrics);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_step == 1 ? "Paso 1: Pega la letra" : "Paso 2: Sincroniza", style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_step == 2)
             IconButton(
               icon: const Icon(Icons.undo),
               onPressed: _currentIndex > 0 ? _undoLine : null,
               tooltip: "Deshacer última línea",
             ),
        ],
      ),
      body: _step == 1 ? _buildStep1() : _buildStep2(),
    );
  }

  Widget _buildStep1() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              maxLines: null,
              expands: true,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: "Pega aquí la letra completa de la canción...\n\nCada renglón o salto de línea será un momento separado en el karaoke.",
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                filled: true,
                fillColor: Colors.grey.shade900,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _goToStep2,
              child: const Text("Comenzar Sincronización", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey.shade900,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white),
                onPressed: () {
                  _audioManager.audioPlayer.seek(_currentPosition - const Duration(seconds: 10));
                },
              ),
              StreamBuilder<bool>(
                stream: _audioManager.audioPlayer.playingStream,
                builder: (context, snapshot) {
                  final isPlaying = snapshot.data ?? false;
                  return IconButton(
                    iconSize: 48,
                    icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: AppColors.accent),
                    onPressed: () {
                      if (isPlaying) {
                        _audioManager.audioPlayer.pause();
                      } else {
                        _audioManager.audioPlayer.play();
                      }
                    },
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white),
                onPressed: () {
                  _audioManager.audioPlayer.seek(_currentPosition + const Duration(seconds: 10));
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 150),
            itemCount: _rawLines.length,
            itemBuilder: (context, index) {
              final isPassed = index < _currentIndex;
              final isCurrent = index == _currentIndex;
              return Padding(
                key: _keys[index],
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  _rawLines[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isCurrent ? 24 : 18,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isPassed 
                        ? AppColors.accent 
                        : (isCurrent ? Colors.white : Colors.white30),
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(24.0),
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black,
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withOpacity(0.2),
                blurRadius: 20,
                spreadRadius: 5,
              )
            ],
          ),
          child: _currentIndex < _rawLines.length
              ? ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _syncNextLine,
                  child: const Text("TOCAR PARA SINCRONIZAR\nLÍNEA ACTUAL", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                )
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _finishAndSave,
                  child: const Text("FINALIZAR Y GUARDAR", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
        ),
      ],
    );
  }
}
