import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/game_screen.dart';
import 'services/ad_service.dart';
import 'services/game_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await GameStorage.instance.load();
  await AdService.instance.initialize();

  runApp(const CarParkingJamApp());
}

class CarParkingJamApp extends StatelessWidget {
  const CarParkingJamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Car Parking Jam 3D',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF0EA5E9),
        useMaterial3: true,
        fontFamily: 'SF Pro Display',
      ),
      home: const GameScreen(),
    );
  }
}
