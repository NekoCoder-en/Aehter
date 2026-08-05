import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import '../theme/app_colors.dart';
import 'video_player_screen.dart';

class VideoListView extends StatefulWidget {
  const VideoListView({super.key});

  @override
  State<VideoListView> createState() => _VideoListViewState();
}

class _VideoListViewState extends State<VideoListView> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  List<File> _videoFiles = [];
  bool _isLoading = true;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndLoad();
  }

  Future<void> _checkPermissionAndLoad() async {
    final status = await Permission.storage.request();
    if (status.isGranted) {
      setState(() => _hasPermission = true);
      _loadVideos();
    } else {
      // Try specific media permissions on newer Android versions
      final videosStatus = await Permission.videos.request();
      if (videosStatus.isGranted) {
        setState(() => _hasPermission = true);
        _loadVideos();
      } else if (videosStatus.isPermanentlyDenied || status.isPermanentlyDenied) {
        await openAppSettings();
        setState(() => _isLoading = false);
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadVideos() async {
    List<File> videos = [];
    try {
      // Manual search for typical video locations
      List<Directory> dirsToCheck = [];
      if (Platform.isAndroid) {
        dirsToCheck.add(Directory('/storage/emulated/0/Movies'));
        dirsToCheck.add(Directory('/storage/emulated/0/Download'));
        dirsToCheck.add(Directory('/storage/emulated/0/DCIM/Camera'));
        dirsToCheck.add(Directory('/storage/emulated/0/WhatsApp/Media/WhatsApp Video'));
        
        final appRecDir = Directory('/storage/emulated/0/Music/AppRec');
        if (appRecDir.existsSync()) dirsToCheck.add(appRecDir);
      }

      for (var dir in dirsToCheck) {
        if (dir.existsSync()) {
          final files = dir.listSync(recursive: true, followLinks: false).whereType<File>();
          for (var file in files) {
            final path = file.path.toLowerCase();
            if (path.endsWith('.mp4') || path.endsWith('.mkv') || path.endsWith('.webm')) {
              videos.add(file);
            }
          }
        }
      }
    } catch (e) {
      print("Error loading videos: \$e");
    }

    if (mounted) {
      setState(() {
        _videoFiles = videos;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text("Se requiere permiso de almacenamiento", style: TextStyle(color: Colors.white)),
            TextButton(
              onPressed: _checkPermissionAndLoad,
              child: const Text("Dar permiso", style: TextStyle(color: AppColors.accent)),
            )
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }

    if (_videoFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_library, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text("No se encontraron videos (.mp4)", style: TextStyle(color: Colors.grey.shade400)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: _videoFiles.length,
      itemBuilder: (context, index) {
        final file = _videoFiles[index];
        final filename = file.path.split('/').last;
        
        return ListTile(
          leading: FutureBuilder<Uint8List?>(
            future: VideoThumbnail.thumbnailData(
              video: file.path,
              imageFormat: ImageFormat.JPEG,
              maxWidth: 100,
              quality: 50,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
                return Container(
                  width: 60,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    image: DecorationImage(
                      image: MemoryImage(snapshot.data!),
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              }
              return Container(
                width: 60,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.play_circle_outline, color: AppColors.accent, size: 30),
              );
            },
          ),
          title: Text(filename, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
          subtitle: Text("Video Local", style: TextStyle(color: Colors.grey.shade500)),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VideoPlayerScreen(
                  videoFiles: _videoFiles,
                  initialIndex: index,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
