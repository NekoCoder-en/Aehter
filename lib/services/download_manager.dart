import 'package:flutter/foundation.dart';
import 'audio_manager.dart';
import 'download_service.dart';

class DownloadTask {
  final String id; // videoId or unique id
  final String title;
  final String? artworkUrl;
  final String? artistName;
  double progress;
  bool isDownloading;
  bool isCompleted;
  bool hasError;

  DownloadTask({
    required this.id,
    required this.title,
    this.artworkUrl,
    this.artistName,
    this.progress = 0.0,
    this.isDownloading = false,
    this.isCompleted = false,
    this.hasError = false,
  });
}

class DownloadManager extends ChangeNotifier {
  final DownloadService _downloadService = DownloadService();
  final List<DownloadTask> _queue = [];
  bool _isProcessing = false;

  List<DownloadTask> get queue => List.unmodifiable(_queue);
  
  int get activeDownloadsCount => _queue.where((t) => t.isDownloading).length;
  bool get hasActiveDownloads => activeDownloadsCount > 0;

  void addDownload(String videoId, String title, {String? artworkUrl, String? artistName}) {
    // Evitar duplicados en cola
    if (_queue.any((t) => t.id == videoId && !t.hasError && !t.isCompleted)) {
      return;
    }
    
    _queue.add(DownloadTask(
      id: videoId,
      title: title,
      artworkUrl: artworkUrl,
      artistName: artistName,
    ));
    notifyListeners();

    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    while (true) {
      // Buscar la siguiente tarea pendiente
      final pendingIndex = _queue.indexWhere((t) => !t.isDownloading && !t.isCompleted && !t.hasError);
      
      if (pendingIndex == -1) {
        break; // No hay más tareas
      }

      final task = _queue[pendingIndex];
      task.isDownloading = true;
      notifyListeners();

      try {
        final path = await _downloadService.downloadAudio(
          task.id,
          task.title,
          task.artworkUrl,
          task.artistName,
          (received, total) {
            if (total != -1) {
              task.progress = received / total;
              notifyListeners();
            }
          },
        );

        if (path != null) {
          task.isCompleted = true;
          task.progress = 1.0;
          
          // Actualizar la lista de música del AudioManager
          try {
            await AudioManager().loadSongs();
            // Wait for Android MediaStore to index the file
            Future.delayed(const Duration(seconds: 3), () {
              AudioManager().loadSongs();
            });
          } catch (e) {
            print("Error reloading songs: $e");
          }
          
          // Auto-remove from queue after a short delay
          Future.delayed(const Duration(seconds: 3), () {
            _queue.removeWhere((t) => t.id == task.id && t.isCompleted);
            notifyListeners();
          });
        } else {
          task.hasError = true;
        }
      } catch (e) {
        print("Error processing download ${task.title}: $e");
        task.hasError = true;
      } finally {
        task.isDownloading = false;
        notifyListeners();
      }
    }

    _isProcessing = false;
  }

  void clearCompleted() {
    _queue.removeWhere((task) => task.isCompleted || task.hasError);
    notifyListeners();
  }
}
