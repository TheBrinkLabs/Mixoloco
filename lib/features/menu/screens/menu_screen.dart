import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../game/screens/game_screen.dart';

/// Placeholder start screen — bar/level select eventually lives here
/// (dodgy bar -> fancier bars as tiers unlock). For now just a way in to
/// the game canvas.
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🍹', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            const Text('Mixoloco',
                style: TextStyle(
                    fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.textLight)),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GameScreen()),
              ),
              child: Container(
                width: 200,
                height: 52,
                decoration: BoxDecoration(
                  gradient: AppColors.gradientSunset,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Text('Play',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
