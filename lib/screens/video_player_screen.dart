import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_colors.dart';

class VideoPlayerScreen extends StatefulWidget {
  final List<File> videoFiles;
  final int initialIndex;

  const VideoPlayerScreen({
    super.key,
    required this.videoFiles,
    required this.initialIndex,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  late int _currentIndex;
  bool _showControls = true;
  bool _isLandscape = false;
  Timer? _hideControlsTimer;
  Timer? _sleepTimer;
  DateTime? _sleepTimerEnd;
  
  final List<double> _playbackSpeeds = [0.5, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _currentIndex = widget.initialIndex;
    _initializePlayer(widget.videoFiles[_currentIndex]);
  }

  void _toggleOrientation() {
    setState(() {
      _isLandscape = !_isLandscape;
    });
    if (_isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeRight,
        DeviceOrientation.landscapeLeft,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  Future<void> _initializePlayer(File file) async {
    if (_controller != null) {
      await _controller!.dispose();
    }

    _controller = VideoPlayerController.file(file);
    await _controller!.initialize();
    
    setState(() {}); // Update UI after initialization
    
    _controller!.play();
    _startHideControlsTimer();

    _controller!.addListener(() {
      if (!mounted) return;
      setState(() {});
      
      // Auto-play next if finished
      if (_controller!.value.isInitialized && 
          _controller!.value.position >= _controller!.value.duration &&
          !_controller!.value.isPlaying) {
        _playNext();
      }
    });
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideControlsTimer();
    }
  }

  void _playNext() {
    if (_currentIndex < widget.videoFiles.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _initializePlayer(widget.videoFiles[_currentIndex]);
    }
  }

  void _playPrevious() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _initializePlayer(widget.videoFiles[_currentIndex]);
    }
  }

  void _seekRelative(int seconds) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final currentPos = _controller!.value.position;
    final targetPos = currentPos + Duration(seconds: seconds);
    _controller!.seekTo(targetPos);
    _startHideControlsTimer();
  }

  void _showSpeedDialog() {
    if (_controller == null) return;
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF282828),
          title: const Text('Velocidad', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _playbackSpeeds.map((speed) {
              return ListTile(
                title: Text('${speed}x', style: const TextStyle(color: Colors.white)),
                onTap: () {
                  _controller!.setPlaybackSpeed(speed);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showSleepTimerDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF282828),
          title: const Text('Temporizador de apagado', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_sleepTimer != null)
                ListTile(
                  title: const Text('Desactivar temporizador', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    _sleepTimer?.cancel();
                    setState(() {
                      _sleepTimer = null;
                      _sleepTimerEnd = null;
                    });
                    Navigator.pop(context);
                  },
                ),
              ...[15, 30, 45, 60].map((minutes) {
                return ListTile(
                  title: Text('$minutes minutos', style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    _sleepTimer?.cancel();
                    
                    final duration = Duration(minutes: minutes);
                    setState(() {
                      _sleepTimerEnd = DateTime.now().add(duration);
                    });

                    _sleepTimer = Timer(duration, () {
                      if (mounted && _controller != null) {
                        _controller!.pause();
                        setState(() {
                          _sleepTimer = null;
                          _sleepTimerEnd = null;
                        });
                      }
                    });
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return duration.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _hideControlsTimer?.cancel();
    _sleepTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filename = widget.videoFiles[_currentIndex].path.split('/').last;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video Player
            if (_controller != null && _controller!.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
              )
            else
              const Center(child: CircularProgressIndicator(color: AppColors.accent)),

            // Controls Overlay
            if (_showControls)
              Container(
                color: Colors.black45,
                child: SafeArea(
                  child: Column(
                    children: [
                      // Top Bar
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                          Expanded(
                            child: Text(
                              filename,
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _sleepTimer != null ? Icons.timer : Icons.timer_outlined,
                              color: _sleepTimer != null ? AppColors.accent : Colors.white,
                            ),
                            onPressed: _showSleepTimerDialog,
                          ),
                          IconButton(
                            icon: const Icon(Icons.speed, color: Colors.white),
                            onPressed: _showSpeedDialog,
                          ),
                          IconButton(
                            icon: Icon(_isLandscape ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
                            onPressed: _toggleOrientation,
                          ),
                        ],
                      ),
                      
                      const Spacer(),
                      
                      // Center Controls
                      if (_controller != null && _controller!.value.isInitialized)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              iconSize: 36,
                              icon: const Icon(Icons.skip_previous, color: Colors.white),
                              onPressed: _currentIndex > 0 ? _playPrevious : null,
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              iconSize: 40,
                              icon: const Icon(Icons.replay_10, color: Colors.white),
                              onPressed: () => _seekRelative(-10),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              iconSize: 56,
                              icon: Icon(
                                _controller!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                                color: AppColors.accent,
                              ),
                              onPressed: () {
                                setState(() {
                                  _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
                                });
                                _startHideControlsTimer();
                              },
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              iconSize: 40,
                              icon: const Icon(Icons.forward_10, color: Colors.white),
                              onPressed: () => _seekRelative(10),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              iconSize: 36,
                              icon: const Icon(Icons.skip_next, color: Colors.white),
                              onPressed: _currentIndex < widget.videoFiles.length - 1 ? _playNext : null,
                            ),
                          ],
                        ),

                      const Spacer(),
                      
                      // Bottom Progress Bar
                      if (_controller != null && _controller!.value.isInitialized)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_formatDuration(_controller!.value.position), style: const TextStyle(color: Colors.white)),
                                  Text(_formatDuration(_controller!.value.duration), style: const TextStyle(color: Colors.white)),
                                ],
                              ),
                              VideoProgressIndicator(
                                _controller!,
                                allowScrubbing: true,
                                colors: const VideoProgressColors(
                                  playedColor: AppColors.accent,
                                  bufferedColor: Colors.grey,
                                  backgroundColor: Colors.white24,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
