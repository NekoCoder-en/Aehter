import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:just_audio/just_audio.dart';
import '../../services/audio_manager.dart';
import '../../theme/app_colors.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final audioManager = context.watch<AudioManager>();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        StreamBuilder<bool>(
          stream: audioManager.audioPlayer.shuffleModeEnabledStream,
          builder: (context, snapshot) {
            final isShuffleOn = snapshot.data ?? false;
            return IconButton(
              icon: FaIcon(
                FontAwesomeIcons.shuffle,
                color: isShuffleOn ? AppColors.primary : Colors.white,
                size: 28,
              ),
              onPressed: audioManager.toggleShuffle,
            );
          },
        ),
        IconButton(
          icon: const FaIcon(
            FontAwesomeIcons.backwardStep,
            color: Colors.white,
            size: 40,
          ),
          onPressed: audioManager.playPrevious,
        ),
        StreamBuilder<bool>(
          stream: audioManager.audioPlayer.playingStream,
          builder: (context, snapshot) {
            final isPlaying = snapshot.data ?? false;
            return IconButton(
              icon: FaIcon(
                isPlaying ? FontAwesomeIcons.pause : FontAwesomeIcons.play,
                color: Colors.white,
                size: 64,
              ),
              onPressed: audioManager.togglePlayPause,
            );
          },
        ),
        IconButton(
          icon: const FaIcon(
            FontAwesomeIcons.forwardStep,
            color: Colors.white,
            size: 40,
          ),
          onPressed: audioManager.playNext,
        ),
        StreamBuilder<LoopMode>(
          stream: audioManager.audioPlayer.loopModeStream,
          builder: (context, snapshot) {
            final loopMode = snapshot.data ?? LoopMode.off;
            return IconButton(
              icon: FaIcon(
                loopMode == LoopMode.one ? FontAwesomeIcons.repeat : FontAwesomeIcons.repeat,
                color: loopMode != LoopMode.off ? AppColors.primary : Colors.white,
                size: 28,
              ),
              onPressed: audioManager.toggleLoop,
            );
          },
        ),
      ],
    );
  }
}
