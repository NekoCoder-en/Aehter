import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_recorder/services/lyrics_service.dart';
import '../screens/lyric_sync_screen.dart';

class KaraokeView extends StatefulWidget {
  final String songPath;
  final String artist;
  final String title;
  final Stream<Duration> positionStream;
  final VoidCallback onClose;

  const KaraokeView({
    super.key,
    required this.songPath,
    required this.artist,
    required this.title,
    required this.positionStream,
    required this.onClose,
  });

  @override
  State<KaraokeView> createState() => _KaraokeViewState();
}

class _KaraokeViewState extends State<KaraokeView> {
  List<SyncedLyric>? _lyrics;
  List<GlobalKey> _lyricKeys = [];
  bool _isLoading = true;
  int _currentIndex = -1;
  int _offsetMilliseconds = 0;

  @override
  void initState() {
    super.initState();
    _loadOffset();
    _loadLyrics();
  }

  @override
  void didUpdateWidget(KaraokeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songPath != widget.songPath) {
      _currentIndex = -1;
      _lyrics = null;
      _lyricKeys = [];
      _loadOffset();
      _loadLyrics();
    }
  }

  Future<void> _loadOffset() async {
    final prefs = await SharedPreferences.getInstance();
    final key = "lyrics_offset_${widget.songPath}";
    setState(() {
      _offsetMilliseconds = prefs.getInt(key) ?? 0;
    });
  }

  Future<void> _saveOffset(int offset) async {
    final prefs = await SharedPreferences.getInstance();
    final key = "lyrics_offset_${widget.songPath}";
    await prefs.setInt(key, offset);
  }

  Future<void> _loadLyrics({bool forceRefresh = false}) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }
    final lyrics = await LyricsService().getLyrics(widget.songPath, widget.artist, widget.title, forceRefresh: forceRefresh);
    if (mounted) {
      setState(() {
        _lyrics = lyrics;
        if (_lyrics != null) {
          _lyricKeys = List.generate(_lyrics!.length, (_) => GlobalKey());
        }
        _isLoading = false;
      });
    }
  }

  void _scrollToCurrentIndex(int index) {
    if (index < 0 || index >= _lyricKeys.length) return;
    
    final key = _lyricKeys[index];
    if (key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.5, // 0.5 means exact center of the viewport
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          color: Colors.black.withValues(alpha: 0.5),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : _lyrics == null || _lyrics!.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              "Letra no disponible o sin conexión",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.refresh),
                              label: const Text("Intentar buscar de nuevo"),
                              onPressed: () => _loadLyrics(forceRefresh: true),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.edit_note, color: Colors.white),
                              label: const Text("Crear letra sincronizada", style: TextStyle(color: Colors.white)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white54),
                              ),
                              onPressed: () async {
                                final bool? created = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LyricSyncScreen(
                                      songPath: widget.songPath,
                                      artist: widget.artist,
                                      title: widget.title,
                                    ),
                                  ),
                                );
                                if (created == true) {
                                  _loadLyrics(forceRefresh: false); // Reload from cache
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    )
                  : StreamBuilder<Duration>(
                      stream: widget.positionStream,
                      builder: (context, snapshot) {
                        final position = (snapshot.data ?? Duration.zero) + Duration(milliseconds: _offsetMilliseconds);
                        
                        // Encontrar el índice activo
                        int newIndex = -1;
                        for (int i = 0; i < _lyrics!.length; i++) {
                          if (position >= _lyrics![i].startTime &&
                              (i == _lyrics!.length - 1 || position < _lyrics![i+1].startTime)) {
                            newIndex = i;
                            break;
                          }
                        }
                        
                        if (newIndex != _currentIndex && newIndex != -1) {
                          _currentIndex = newIndex;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _scrollToCurrentIndex(_currentIndex);
                          });
                        }

                        return SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                            vertical: 150, // Mucho espacio arriba y abajo para que pueda centrarse incluso la primera y última línea
                            horizontal: 16,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: List.generate(_lyrics!.length, (index) {
                              final lyric = _lyrics![index];
                              final isActive = index == _currentIndex;
                              final isPassed = index < _currentIndex;
                              
                              return Padding(
                                key: _lyricKeys[index],
                                padding: const EdgeInsets.symmetric(vertical: 8.0),
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 300),
                                  style: TextStyle(
                                    fontSize: isActive ? 22 : 18,
                                    fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
                                    color: isActive
                                        ? Colors.white
                                        : (isPassed ? Colors.white70 : Colors.white30),
                                    height: 1.3,
                                    shadows: isActive ? [
                                      Shadow(
                                        color: Colors.white.withValues(alpha: 0.5),
                                        blurRadius: 8,
                                      )
                                    ] : null,
                                  ),
                                  textAlign: TextAlign.center,
                                  child: Text(lyric.text),
                                ),
                              );
                            }),
                          ),
                        );
                      },
                    ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.edit_note, color: Colors.white54),
                onPressed: () async {
                  final bool? created = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LyricSyncScreen(
                        songPath: widget.songPath,
                        artist: widget.artist,
                        title: widget.title,
                      ),
                    ),
                  );
                  if (created == true) {
                    _loadLyrics(forceRefresh: false);
                  }
                },
                tooltip: "Letra incorrecta? Crea la tuya",
              ),
              IconButton(
                icon: const Icon(Icons.sync, color: Colors.white54),
                onPressed: () => _loadLyrics(forceRefresh: true),
                tooltip: "Buscar letra en internet de nuevo",
              ),
            ],
          ),
        ),
        if (_lyrics != null && _lyrics!.isNotEmpty)
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove, color: Colors.white, size: 20),
                    onPressed: () {
                      setState(() => _offsetMilliseconds -= 500);
                      _saveOffset(_offsetMilliseconds);
                    },
                    tooltip: "Atrasar letras",
                  ),
                  Text(
                    "${(_offsetMilliseconds / 1000).toStringAsFixed(1)}s",
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white, size: 20),
                    onPressed: () {
                      setState(() => _offsetMilliseconds += 500);
                      _saveOffset(_offsetMilliseconds);
                    },
                    tooltip: "Adelantar letras",
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
