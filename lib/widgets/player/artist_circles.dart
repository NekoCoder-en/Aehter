import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart' as ytmusic;
import 'package:cached_network_image/cached_network_image.dart';

import '../../theme/app_colors.dart';

/// Fila de círculos de artista mostrada en la hoja de opciones del reproductor.
/// Cada nombre de artista se resuelve de forma independiente: si no se
/// encuentra su foto de canal (sin red, sin resultados, error de YouTube),
/// se muestra un avatar con sus iniciales en vez de desaparecer la fila
/// entera — así "los nombres y fotos" siempre se ven, aunque la búsqueda falle.
class ArtistCircles extends StatelessWidget {
  final String rawArtists;
  const ArtistCircles({super.key, required this.rawArtists});

  static final RegExp _separators = RegExp(
    r'[,&/]|\bfeat\.?\b|\bft\.?\b|\bwith\b|\bx\b|\bvs\.?\b',
    caseSensitive: false,
  );

  List<String> get _artistNames => rawArtists
      .split(_separators)
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

  @override
  Widget build(BuildContext context) {
    final names = _artistNames;
    if (names.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: names
            .map((name) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0),
                  child: _ArtistAvatar(name: name),
                ))
            .toList(),
      ),
    );
  }
}

class _ArtistAvatar extends StatefulWidget {
  final String name;
  const _ArtistAvatar({required this.name});

  @override
  State<_ArtistAvatar> createState() => _ArtistAvatarState();
}

class _ArtistAvatarState extends State<_ArtistAvatar> {
  // Cache en memoria compartida entre todas las hojas abiertas durante la sesión.
  static final Map<String, Future<String?>> _photoCache = {};

  late final Future<String?> _photoFuture;

  @override
  void initState() {
    super.initState();
    final key = widget.name.trim().toLowerCase();
    _photoFuture = _photoCache.putIfAbsent(key, () => _fetchChannelPhoto(widget.name));
  }

  static Future<String?> _fetchChannelPhoto(String name) async {
    // 1. YouTube Music tiene búsqueda de artista dedicada — mucho más confiable
    // para músicos que la búsqueda genérica de canales de YouTube, en especial
    // con nombres cortos/ambiguos (ej. "Ado") donde la búsqueda de canales
    // devuelve resultados sin relación con la artista real.
    try {
      final ytm = ytmusic.YTMusic();
      await ytm.initialize();
      final results = await ytm.search(name);
      final artistResult = results.whereType<ytmusic.ArtistDetailed>().firstOrNull;
      if (artistResult != null && artistResult.thumbnails.isNotEmpty) {
        return artistResult.thumbnails.last.url;
      }
    } catch (_) {
      // sigue al respaldo de YouTube más abajo
    }

    // 2. Respaldo: búsqueda de canales de YouTube.
    YoutubeExplode? yt;
    try {
      yt = YoutubeExplode();
      final channelResults = await yt.search.searchContent(name, filter: TypeFilters.channel);
      final channels = channelResults.whereType<SearchChannel>().toList();
      if (channels.isEmpty) return null;

      // Para nombres cortos/genéricos (ej. "Ado") la búsqueda puede devolver
      // varios canales sin relación con la artista. En vez de quedarnos con
      // el primero de la lista, entre los candidatos que matchean por nombre
      // preferimos el que tenga más videos: una señal simple de que es el
      // canal real/establecido y no uno de fans o al azar.
      SearchChannel pickMostEstablished(Iterable<SearchChannel> candidates) =>
          candidates.reduce((a, b) => a.videoCount >= b.videoCount ? a : b);

      final normalizedName = name.trim().toLowerCase();
      final exactMatches = channels.where((c) => c.name.trim().toLowerCase() == normalizedName);
      final looseMatches = channels.where(
        (c) => c.name.toLowerCase().contains('vevo') || c.name.toLowerCase().contains(normalizedName),
      );

      final best = exactMatches.isNotEmpty
          ? pickMostEstablished(exactMatches)
          : looseMatches.isNotEmpty
              ? pickMostEstablished(looseMatches)
              : pickMostEstablished(channels);
      final channel = await yt.channels.get(best.id);
      return channel.logoUrl;
    } catch (_) {
      // Sin red, error de YouTube, etc: se resuelve como "sin foto" y el
      // avatar cae al respaldo de iniciales, nunca desaparece la fila.
      return null;
    } finally {
      yt?.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FutureBuilder<String?>(
          future: _photoFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return _AvatarRing(child: _LoadingPulse());
            }
            final url = snapshot.data;
            if (url == null) {
              return _AvatarRing(child: _InitialsAvatar(name: widget.name));
            }
            return _AvatarRing(
              child: ClipOval(
                child: CachedNetworkImage(
                  imageUrl: url,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => _InitialsAvatar(name: widget.name),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 72,
          child: Text(
            widget.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

/// Anillo con degradé neón alrededor del avatar, consistente con el tema de la app.
class _AvatarRing extends StatelessWidget {
  final Widget child;
  const _AvatarRing({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.neonGradient,
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.2), blurRadius: 8, spreadRadius: 0.5),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF282828)),
        child: ClipOval(child: SizedBox(width: 56, height: 56, child: child)),
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  final String name;
  const _InitialsAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      color: const Color(0xFF3A3A3A),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _LoadingPulse extends StatefulWidget {
  @override
  State<_LoadingPulse> createState() => _LoadingPulseState();
}

class _LoadingPulseState extends State<_LoadingPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 0.7).animate(_controller),
      child: const ColoredBox(color: Color(0xFF3A3A3A)),
    );
  }
}
