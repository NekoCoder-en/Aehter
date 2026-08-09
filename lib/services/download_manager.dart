import 'package:flutter/foundation.dart';
import 'audio_manager.dart';
import 'download_service.dart';

class DownloadTask {
  final String id; // videoId or unique id
  final String title;
  final String? artworkUrl;
  final String? artistName;
  final bool isVideo;
  final int? itag; // calidad específica elegida, solo para isVideo
  double progress;
  bool isDownloading;
  bool isCompleted;
  bool hasError;

  DownloadTask({
    required this.id,
    required this.title,
    this.artworkUrl,
    this.artistName,
    this.isVideo = false,
    this.itag,
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
    // Evitar duplicados en cola (compara también isVideo: el mismo video se
    // puede pedir como audio y como video sin que se pisen entre sí).
    if (_queue.any((t) => t.id == videoId && !t.isVideo && !t.hasError && !t.isCompleted)) {
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

  void addVideoDownload(String videoId, String title, {String? artworkUrl, int? itag}) {
    // Evitar duplicados en cola: misma calidad (itag) del mismo video.
    if (_queue.any((t) => t.id == videoId && t.isVideo && t.itag == itag && !t.hasError && !t.isCompleted)) {
      return;
    }

    _queue.add(DownloadTask(
      id: videoId,
      title: title,
      artworkUrl: artworkUrl,
      isVideo: true,
      itag: itag,
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
        void onProgress(int received, int total) {
          if (total != -1) {
            task.progress = received / total;
            notifyListeners();
          }
        }

        final path = task.isVideo
            ? await _downloadService.downloadVideo(task.id, task.title, onProgress, itag: task.itag)
            : await _downloadService.downloadAudio(
                task.id,
                task.title,
                task.artworkUrl,
                task.artistName,
                onProgress,
              );

        if (path != null) {
          task.isCompleted = true;
          task.progress = 1.0;

          if (!task.isVideo) {
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
          }

          // Auto-remove from queue after a short delay. Compara por identidad
          // (no solo por id): el mismo video puede tener a la vez una tarea
          // de audio y otra de video, y no deben pisarse entre sí.
          Future.delayed(const Duration(seconds: 3), () {
            _queue.removeWhere((t) => identical(t, task));
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

  /// Saca de la cola las tareas con error de un video/canción puntual, para
  /// poder reintentar la descarga desde cero (si no, el dedup de
  /// addDownload/addVideoDownload seguiría viendo la tarea vieja).
  void clearError(String id) {
    _queue.removeWhere((task) => task.id == id && task.hasError);
    notifyListeners();
  }
}
