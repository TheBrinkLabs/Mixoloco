import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'features/menu/screens/menu_screen.dart';

void main() {
  runApp(const ProviderScope(child: MixolocoApp()));
}

class MixolocoApp extends StatelessWidget {
  const MixolocoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mixoloco',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const MenuScreen(),
    );
  }
}
