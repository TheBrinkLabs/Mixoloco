import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart' show AppLocale;
import '../../../core/services/share_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bar_backdrop.dart' show headerBoardRect, kEmptyTabAspect;
import '../../../core/widgets/glass_visual.dart';
import '../../../core/widgets/notification_tablet.dart' show StoneButton;
import '../../../core/widgets/submenu_kit.dart';
import '../../../data/models/ingredient.dart';
import '../providers/game_state_provider.dart';

/// The one-time "finished the whole game" celebration — a confetti burst
/// plus a bigger gold-bordered title than the ordinary game-over screen
/// ever shows, since finishing all 4 levels is a different occasion than
/// just losing a run. Reuses _GameOverOverlay's layout math (panel width,
/// topClearance, the same 4 stat rows) in game_screen.dart almost exactly,
/// but is its own widget rather than a branch inside that one, since the
/// confetti/title treatment is substantial enough to want its own file.
class GameCompleteOverlay extends StatefulWidget {
  final BoardState board;
  final VoidCallback onHome;
  final AppLocale locale;

  /// The end-of-game +500 credits ad button (see EndGameBonusButton).
  final Widget bonus;
  const GameCompleteOverlay({
    super.key,
    required this.board,
    required this.onHome,
    required this.locale,
    required this.bonus,
  });

  @override
  State<GameCompleteOverlay> createState() => _GameCompleteOverlayState();
}

class _GameCompleteOverlayState extends State<GameCompleteOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _confettiController;
  late final List<_ConfettiPiece> _confettiPieces;

  @override
  void initState() {
    super.initState();
    _confettiController = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))..forward();
    _confettiPieces = List.generate(48, (_) => _ConfettiPiece.random());
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final board = widget.board;
    final locale = widget.locale;
    final screenSize = MediaQuery.sizeOf(context);
    final screenWidth = screenSize.width;
    const sideMargin = 28.0;
    final panelWidth = screenWidth - sideMargin * 2;
    final chain = evolutionChainForLevel(board.level);
    final maxEvoIngredient = chain[board.runHighestTier.clamp(0, chain.length - 1)];
    const valueStyle = TextStyle(fontFamily: 'Lilita One', fontSize: 18, color: SubmenuColors.gold);
    // Same math as _GameOverOverlay — keeps this clear of the live HUD
    // (credits/score pills, action tiles, progress row) still showing
    // through the dim behind it.
    final boardRect = headerBoardRect(screenSize);
    final progressTabWidth = (screenWidth - 20 - 21) / 8;
    final progressTabHeight = (progressTabWidth / kEmptyTabAspect) * 1.2;
    final topClearance = boardRect.top + boardRect.height + 3 + progressTabHeight + 14;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.45),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _confettiController,
                  builder: (context, _) => CustomPaint(
                    size: Size.infinite,
                    painter: _ConfettiPainter(pieces: _confettiPieces, t: _confettiController.value),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  SizedBox(height: topClearance),
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topCenter,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 30),
                        child: SizedBox(
                          width: panelWidth,
                          child: SubmenuPanel(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InsetList(
                                  rows: [
                                    SubmenuRow(
                                      icon: Icons.star_rounded,
                                      label: tr(locale, 'score_label'),
                                      trailing: Text('${board.score}', style: valueStyle),
                                    ),
                                    SubmenuRow(
                                      icon: Icons.flag_rounded,
                                      label: tr(locale, 'level'),
                                      trailing: Text('${board.level}', style: valueStyle),
                                    ),
                                    SubmenuRow(
                                      icon: Icons.auto_awesome_rounded,
                                      label: tr(locale, 'max_evo_label'),
                                      trailing: GlassVisual(ingredient: maxEvoIngredient, size: 34, applyDisplayScale: false),
                                    ),
                                    SubmenuRow(
                                      icon: Icons.local_bar_rounded,
                                      label: tr(locale, 'cocktails_made_label'),
                                      trailing: Text('${board.cocktailsMade}', style: valueStyle),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                widget.bonus,
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: StoneButton(
                                        onTap: () => shareText(tr(locale, 'share_score_text').replaceFirst('{score}', '${board.score}')),
                                        height: 50,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.share_rounded, size: 18, color: Colors.black),
                                            const SizedBox(width: 6),
                                            Text(tr(locale, 'share'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black)),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: StoneButton(
                                        onTap: widget.onHome,
                                        height: 50,
                                        child: Text(
                                          tr(locale, 'main_menu'),
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.4, end: 1.0),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.elasticOut,
                        builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(36, 10, 36, 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: SubmenuColors.goldEdge, width: 4),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [SubmenuColors.goldTop, SubmenuColors.goldBottom],
                            ),
                            boxShadow: [
                              BoxShadow(color: SubmenuColors.goldEdge, offset: const Offset(0, 5)),
                              BoxShadow(color: Colors.black.withValues(alpha: 0.4), offset: const Offset(0, 10), blurRadius: 20),
                            ],
                          ),
                          child: OutlinedLabel(
                            text: tr(locale, 'game_complete_title').toUpperCase(),
                            fontSize: 36,
                            fill: Colors.white,
                            stroke: SubmenuColors.goldEdge,
                            strokeWidth: 6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 110),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Same confetti burst as LevelUpOverlay's own celebration — duplicated
/// rather than exported/un-privatized from there, so this one-time finale
/// doesn't risk touching the per-level flow at all.
class _ConfettiPiece {
  _ConfettiPiece({
    required this.angle,
    required this.speed,
    required this.color,
    required this.size,
    required this.spinSpeed,
    required this.startDelay,
  });

  final double angle;
  final double speed;
  final Color color;
  final double size;
  final double spinSpeed;
  final double startDelay;

  static final _colors = [AppColors.sunsetGold, AppColors.sunsetOrange, Colors.pinkAccent, Colors.lightBlueAccent, Colors.greenAccent];

  factory _ConfettiPiece.random() {
    final r = Random();
    return _ConfettiPiece(
      angle: r.nextDouble() * pi * 2,
      speed: 0.55 + r.nextDouble() * 0.55,
      color: _colors[r.nextInt(_colors.length)],
      size: 5 + r.nextDouble() * 5,
      spinSpeed: (r.nextDouble() - 0.5) * 14,
      startDelay: r.nextDouble() * 0.15,
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.pieces, required this.t});
  final List<_ConfettiPiece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.4);
    final scale = size.shortestSide;
    for (final p in pieces) {
      final localT = ((t - p.startDelay) / (1 - p.startDelay)).clamp(0.0, 1.0);
      if (localT <= 0) continue;
      final dx = cos(p.angle) * p.speed * scale * 0.6 * localT;
      final dy = sin(p.angle) * p.speed * scale * 0.35 * localT + 0.5 * scale * localT * localT;
      final opacity = (1 - localT).clamp(0.0, 1.0);
      final paint = Paint()..color = p.color.withValues(alpha: opacity);
      canvas.save();
      canvas.translate(center.dx + dx, center.dy + dy);
      canvas.rotate(p.spinSpeed * localT);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => oldDelegate.t != t;
}
