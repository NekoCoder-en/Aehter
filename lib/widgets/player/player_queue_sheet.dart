import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:io';
import 'package:on_audio_query/on_audio_query.dart';
import '../../services/audio_manager.dart';
import '../../theme/app_colors.dart';

class PlayerQueueSheet extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final Color bgColor;

  const PlayerQueueSheet({
    Key? key,
    required this.isExpanded,
    required this.onToggle,
    required this.onDragUpdate,
    required this.bgColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final audioManager = context.watch<AudioManager>();

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      bottom: isExpanded ? 0 : -(MediaQuery.of(context).size.height * 0.77),
      left: 0,
      right: 0,
      height: MediaQuery.of(context).size.height * 0.85,
      child: GestureDetector(
        onVerticalDragUpdate: onDragUpdate,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: bgColor.withOpacity(0.6), // Glassmorphism using dominant color
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
                ),
              ),
              child: Column(
                children: [
                  // Handle
                  GestureDetector(
                    onTap: onToggle,
                    child: Container(
                      width: double.infinity,
                      color: Colors.transparent, // Larger hit area
                      child: Column(
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 16, bottom: 12),
                            width: 48,
                            height: 6,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          const Text(
                            'Siguiente en la cola',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: audioManager.queue.isEmpty
                        ? const Center(child: Text("La cola está vacía", style: TextStyle(color: Colors.grey)))
                        : Theme(
                            data: Theme.of(context).copyWith(
                              canvasColor: Colors.transparent,
                            ),
                            child: ReorderableListView.builder(
                              physics: isExpanded ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics(),
                              itemCount: audioManager.queue.length,
                              onReorder: audioManager.reorderQueue,
                              padding: const EdgeInsets.only(bottom: 24),
                              proxyDecorator: (child, index, animation) {
                                return Material(
                                  color: Colors.transparent,
                                  elevation: 8,
                                  child: child,
                                );
                              },
                              itemBuilder: (context, index) {
                                final qSong = audioManager.queue[index];
                                final isPlaying = index == audioManager.currentIndex;
                                final qMetadata = audioManager.simulatedMetadata[qSong.data];
                                final qArtist = qMetadata != null ? qMetadata['artist'] : (qSong.artist ?? "Desconocido");
                                final qTitle = qMetadata != null ? qMetadata['title'] : qSong.title;

                                  final String? rawArtwork = qMetadata != null ? qMetadata['artworkUrl'] : null;
                                  final artworkUrl = rawArtwork?.replaceFirst(RegExp(r'=w\d+-h\d+'), '=w150-h150');

                                  Widget artworkWidget;
                                  if (artworkUrl != null) {
                                    artworkWidget = artworkUrl.startsWith('file://') 
                                      ? Image.file(
                                          File(artworkUrl.replaceFirst('file://', '')),
                                          width: 50, height: 50, fit: BoxFit.cover,
                                        )
                                      : Image.network(
                                          artworkUrl,
                                          width: 50, height: 50, fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => QueryArtworkWidget(
                                            id: qSong.id,
                                            type: ArtworkType.AUDIO,
                                            artworkWidth: 50,
                                            artworkHeight: 50,
                                            size: 200,
                                            nullArtworkWidget: Container(
                                              width: 50, height: 50,
                                              color: Colors.grey.shade800,
                                              child: const Center(child: FaIcon(FontAwesomeIcons.music, size: 20, color: Colors.grey)),
                                            ),
                                          ),
                                        );
                                  } else {
                                    artworkWidget = QueryArtworkWidget(
                                      id: qSong.id,
                                      type: ArtworkType.AUDIO,
                                      artworkWidth: 50,
                                      artworkHeight: 50,
                                      size: 200,
                                      nullArtworkWidget: Container(
                                        width: 50, height: 50,
                                        color: Colors.grey.shade800,
                                        child: const Center(child: FaIcon(FontAwesomeIcons.music, size: 20, color: Colors.grey)),
                                      ),
                                    );
                                  }

                                  return Dismissible(
                                    key: ValueKey('${qSong.id}_$index'),
                                    direction: DismissDirection.endToStart,
                                    onDismissed: (_) => audioManager.removeFromQueue(index),
                                    background: Container(
                                      color: Colors.red,
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 20),
                                      child: const Icon(Icons.delete, color: Colors.white),
                                    ),
                                    child: Material(
                                      type: MaterialType.transparency,
                                      child: ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                                        leading: ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: SizedBox(
                                            width: 50, height: 50,
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                artworkWidget,
                                                if (isPlaying)
                                                  Container(
                                                    color: Colors.black.withOpacity(0.6),
                                                    child: const Center(
                                                      child: FaIcon(FontAwesomeIcons.volumeHigh, color: AppColors.primary, size: 20),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        title: Text(
                                          qTitle,
                                          style: TextStyle(
                                            color: isPlaying ? AppColors.primary : Colors.white,
                                            fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          qArtist,
                                          style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        trailing: const Icon(Icons.drag_handle, color: Colors.grey),
                                        onTap: () {
                                          audioManager.playQueue(audioManager.queue, index);
                                        },
                                      ),
                                    ),
                                  );
                                },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
