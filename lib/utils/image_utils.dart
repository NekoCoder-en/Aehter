import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:on_audio_query/on_audio_query.dart';

class ImageUtils {
  static final Map<int, Color> _colorCache = {};

  static Future<Color> getDominantColor(int songId, {String? imageUrl}) async {
    if (_colorCache.containsKey(songId)) {
      return _colorCache[songId]!;
    }

    try {
      ImageProvider imageProvider;
      
      if (imageUrl != null) {
        if (imageUrl.startsWith('file://')) {
          imageProvider = FileImage(File(imageUrl.replaceFirst('file://', '')));
        } else {
          imageProvider = NetworkImage(imageUrl);
        }
      } else {
        final Uint8List? artwork = await OnAudioQuery().queryArtwork(
          songId,
          ArtworkType.AUDIO,
          size: 200,
        );
        if (artwork == null) return Colors.grey.shade900;
        imageProvider = MemoryImage(artwork);
      }

      final PaletteGenerator paletteGenerator = await PaletteGenerator.fromImageProvider(
        imageProvider,
      );
      Color color = paletteGenerator.darkMutedColor?.color ?? 
                    paletteGenerator.darkVibrantColor?.color ?? 
                    paletteGenerator.dominantColor?.color ?? 
                    Colors.grey.shade900;
      
      // Ensure the color is dark enough so white text remains readable
      HSLColor hsl = HSLColor.fromColor(color);
      if (hsl.lightness > 0.3) {
        color = hsl.withLightness(0.3).toColor();
      }
      
      _colorCache[songId] = color;
      return color;
    } catch (e) {
      print("Error getting color: $e");
    }

    return Colors.grey.shade900;
  }
}
