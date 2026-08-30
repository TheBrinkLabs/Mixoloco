import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../mixoloco_game.dart';

class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: GameWidget(game: MixolocoGame()),
      ),
    );
  }
}
