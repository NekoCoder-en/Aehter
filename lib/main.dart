import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:screen_recorder/services/audio_manager.dart';
import 'package:screen_recorder/services/download_manager.dart';
import 'package:screen_recorder/services/playlist_manager.dart';
import 'package:screen_recorder/screens/home_screen.dart';

import 'package:just_audio_background/just_audio_background.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );

  final playlistManager = PlaylistManager();
  await playlistManager.loadPlaylists();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AudioManager()),
        ChangeNotifierProvider(create: (_) => DownloadManager()),
        ChangeNotifierProvider.value(value: playlistManager),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aether Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
