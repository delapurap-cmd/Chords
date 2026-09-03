import 'package:flutter/material.dart';

import 'ejercicio/ejercicio_page.dart';

void main() {
  runApp(const ChordsApp());
}

class ChordsApp extends StatelessWidget {
  const ChordsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chords',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD4C46A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const EjercicioPage(),
    );
  }
}
