import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/widgets/banner_ad_widget.dart' show blockBanner, unblockBanner;
import '../../../core/widgets/glass_visual.dart';
import '../../../core/widgets/submenu_kit.dart';
import '../../../data/models/ingredient.dart';

/// The Guide's "How to Play": a walkthrough video of real gameplay
/// (assets/videos/how_to_play.mp4, cut from device recordings — see the
/// timeline below) with a hand, merge rings, the line, the chain and
/// captions drawn on top by the app, so they're sharp and in the player's
/// language. Each part holds for two seconds before the next (baked into
/// the video); arrows either side step back and forward a part.
class HowToPlayScreen extends ConsumerStatefulWidget {
  const HowToPlayScreen({super.key});

  @override
  ConsumerState<HowToPlayScreen> createState() => _HowToPlayScreenState();
}

class _HowToPlayScreenState extends ConsumerState<HowToPlayScreen> with SingleTickerProviderStateMixin {
  late final VideoPlayerController _video = VideoPlayerController.asset('assets/videos/how_to_play.mp4');

  /// Where the walkthrough is, in content seconds (the timeline below),
  /// updated every frame. The player only reports its position a few times
  /// a second, so between reports this runs on from the last one by the
  /// time elapsed — that's what keeps the hand gliding rather than stepping.
  final _time = ValueNotifier<double>(0);

  /// The rings' and line's pulse — on its own clock, so they keep pulsing
  /// through the holds between parts.
  final _pulse = ValueNotifier<double>(0);
  final _clock = Stopwatch()..start();
  double _reported = -1;
  final _sinceReport = Stopwatch();
  late final Ticker _ticker = createTicker((_) => _tick());
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // No banner ad while the guide plays: a video banner decoding alongside
    // the walkthrough made it stall, and the banner covered the screen's
    // bottom. Deferred, as GameScreen does — a provider write isn't safe
    // inside initState/dispose.
    blockBanner();
    _video.setVolume(0);
    _video.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _video.play();
      _ticker.start();
    }).catchError((Object _) {
      // A device that can't play the video: close rather than leave a
      // spinner (on first launch, the first thing a new player sees).
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    unblockBanner();
    _ticker.dispose();
    _video.dispose();
    _time.dispose();
    _pulse.dispose();
    super.dispose();
  }

  double get _videoDuration => _video.value.duration.inMilliseconds / 1000;

  void _tick() {
    _pulse.value = 0.5 + 0.5 * _wave(_clock.elapsedMilliseconds / 1000 * 3);
    final v = _video.value;
    if (!v.isInitialized) return;
    final pos = v.position.inMilliseconds / 1000;
    // Mid-jump, the player still reports where it was — stay at the target
    // until it catches up.
    final target = _seekTarget;
    if (target != null) {
      if ((pos - target).abs() > 0.3) return;
      _seekTarget = null;
    }
    if (pos != _reported) {
      _reported = pos;
      _sinceReport
        ..reset()
        ..start();
    }
    var t = pos;
    if (v.isPlaying) t += _sinceReport.elapsedMilliseconds / 1000;
    if (_videoDuration > 0 && t > _videoDuration) t = _videoDuration;
    _time.value = _contentAt(t);
  }

  double? _seekTarget;

  /// Jumps to content time [seconds]: pauses, seeks, then plays — each step
  /// awaited (fired together, the picture stayed frozen on the old frame).
  Future<void> _seek(double seconds) async {
    final target = _videoAt(seconds).clamp(0.0, _videoDuration);
    _seekTarget = target;
    _time.value = seconds;
    _reported = -1;
    await _video.pause();
    await _video.seekTo(Duration(milliseconds: (target * 1000).round()));
    if (!mounted) return;
    await _video.play();
  }

  void _step(int direction) {
    final t = _time.value;
    final starts = [for (final c in _captions) c.start];
    var i = starts.lastIndexWhere((s) => s <= t + 0.05);
    if (i < 0) i = 0;
    if (direction > 0) {
      if (i + 1 < starts.length) _seek(starts[i + 1]);
    } else {
      // Well into a part, back goes to its start; near the start, to the
      // one before.
      _seek(t - starts[i] > 0.8 || i == 0 ? starts[i] : starts[i - 1]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final insets = MediaQuery.paddingOf(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0B2238),
      body: Padding(
        padding: EdgeInsets.fromLTRB(8, insets.top + 10, 8, insets.bottom + 16),
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 8),
                SubmenuBackButton(icon: Icons.close_rounded, onTap: () => Navigator.of(context).maybePop()),
                Expanded(
                  child: Text(
                    tr(locale, 'how_to_play'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Lilita One', fontSize: 24, color: SubmenuColors.goldTop),
                  ),
                ),
                GoldArrowButton(icon: Icons.replay_rounded, enabled: _ready, onTap: () => _seek(0), size: 46),
                const SizedBox(width: 8),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                children: [
                  GoldArrowButton(icon: Icons.chevron_left_rounded, enabled: _ready, onTap: () => _step(-1), size: 44),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 576 / 1280,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: SubmenuColors.gold, width: 3),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: _ready
                                ? LayoutBuilder(
                                    builder: (context, box) => Stack(
                                      children: [
                                        Positioned.fill(child: VideoPlayer(_video)),
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: ListenableBuilder(
                                              listenable: Listenable.merge([_time, _pulse]),
                                              builder: (context, _) => Stack(children: _overlays(_time.value, box.biggest)),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : const Center(child: CircularProgressIndicator(color: SubmenuColors.gold)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GoldArrowButton(icon: Icons.chevron_right_rounded, enabled: _ready, onTap: () => _step(1), size: 44),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                height: 150,
                child: ValueListenableBuilder<double>(
                  valueListenable: _time,
                  builder: (context, t, _) {
                    final caption = _captionAt(t);
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: caption == null
                          ? const SizedBox.shrink()
                          : _CaptionPanel(
                              key: ValueKey(caption.start),
                              title: tr(locale, caption.title),
                              text: tr(locale, caption.text),
                            ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Everything drawn over the video ([size]) at time [t].
  List<Widget> _overlays(double t, Size size) {
    final widgets = <Widget>[];
    final pulse = _pulse.value;

    if (t >= _lineStart && t < _lineEnd) widgets.add(_line(size, pulse));
    if (t >= _chainStart && t < _chainEnd) widgets.add(_chain(t, size));

    for (final h in _highlights) {
      if (t < h.start || t > h.end) continue;
      final r = h.rect;
      widgets.add(Positioned(
        left: r.left * size.width,
        top: r.top * size.height,
        width: r.width * size.width,
        height: r.height * size.height,
        child: Transform.scale(
          // A merge ring swells as it pulses; button outlines just glow.
          scale: h.circle ? 0.9 + 0.25 * pulse : 1.0,
          child: Container(
            decoration: BoxDecoration(
              shape: h.circle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: h.circle ? null : BorderRadius.circular(14),
              border: Border.all(color: SubmenuColors.goldTop.withValues(alpha: 0.6 + 0.4 * pulse), width: 3 + 2 * pulse),
              boxShadow: [BoxShadow(color: SubmenuColors.goldTop.withValues(alpha: 0.35 * pulse), blurRadius: 14)],
            ),
          ),
        ),
      ));
    }

    final hand = _handAt(t);
    if (hand != null && hand.opacity > 0) {
      final s = size.width * 0.17;
      final tip = Offset(hand.x * size.width, hand.y * size.height);
      if (hand.down) {
        widgets.add(Positioned(
          left: tip.dx - s * 0.32,
          top: tip.dy - s * 0.32,
          width: s * 0.64,
          height: s * 0.64,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.28 * hand.opacity),
              border: Border.all(color: Colors.white.withValues(alpha: 0.8 * hand.opacity), width: 2),
            ),
          ),
        ));
      }
      // touch_app's fingertip sits about 45% across and 10% down its box.
      widgets.add(Positioned(
        left: tip.dx - s * 0.45,
        top: tip.dy - s * 0.10,
        width: s,
        height: s,
        child: Opacity(
          opacity: hand.opacity,
          child: Transform.scale(
            scale: hand.down ? 0.88 : 1.0,
            alignment: const Alignment(-0.1, -0.8),
            child: Icon(
              Icons.touch_app_rounded,
              size: s,
              color: Colors.white,
              shadows: const [Shadow(color: Colors.black87, blurRadius: 8, offset: Offset(2, 3))],
            ),
          ),
        ),
      ));
    }
    return widgets;
  }

  /// The game-over line, flashing red.
  Widget _line(Size size, double pulse) {
    const thickness = 6.0;
    return Positioned(
      left: _lineLeft * size.width,
      width: (_lineRight - _lineLeft) * size.width,
      top: _lineY * size.height - thickness / 2,
      height: thickness,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(thickness),
          color: Color.lerp(const Color(0xFF8E1B12), const Color(0xFFFF3B30), pulse),
          boxShadow: [BoxShadow(color: const Color(0xFFFF3B30).withValues(alpha: 0.75 * pulse), blurRadius: 16, spreadRadius: 2)],
        ),
      ),
    );
  }

  /// The Beach chain, smallest to final item, appearing one step at a time
  /// over the dimmed table.
  Widget _chain(double t, Size size) {
    final chain = evolutionChainForLevel(1);
    final item = size.width * 0.15;
    final fade = ((t - _chainStart) / 0.3).clamp(0.0, 1.0);
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55 * fade),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: item * 0.25,
          children: [
            for (var i = 0; i < chain.length; i++) ...[
              _ChainItem(
                ingredient: chain[i],
                size: i == chain.length - 1 ? item * 1.35 : item,
                shown: ((t - _chainStart - 0.4 - i * _chainStepEvery) / 0.25).clamp(0.0, 1.0),
                finalItem: i == chain.length - 1,
              ),
              if (i < chain.length - 1)
                Opacity(
                  opacity: ((t - _chainStart - 0.4 - (i + 0.5) * _chainStepEvery) / 0.25).clamp(0.0, 1.0),
                  child: Icon(Icons.chevron_right_rounded, color: SubmenuColors.goldTop, size: item * 0.4),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChainItem extends StatelessWidget {
  final Ingredient ingredient;
  final double size;
  final double shown;
  final bool finalItem;
  const _ChainItem({required this.ingredient, required this.size, required this.shown, required this.finalItem});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: shown,
      child: Transform.scale(
        scale: 0.6 + 0.4 * Curves.easeOutBack.transform(shown),
        child: Container(
          padding: EdgeInsets.all(size * 0.08),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.25),
            color: SubmenuColors.inset,
            border: Border.all(color: finalItem ? SubmenuColors.goldTop : Colors.transparent, width: 2),
          ),
          child: GlassVisual(ingredient: ingredient, size: size, applyDisplayScale: false),
        ),
      ),
    );
  }
}

class _CaptionPanel extends StatelessWidget {
  final String title;
  final String text;
  const _CaptionPanel({super.key, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SubmenuColors.gold, width: 2),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2364A0), SubmenuColors.panelBottom],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(fontFamily: 'Lilita One', fontSize: 22, color: SubmenuColors.goldTop)),
          const SizedBox(height: 4),
          // Shrinks to fit rather than cutting off a long translation.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: submenuNunito(size: 14, weight: FontWeight.w800, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

double _wave(double x) => (1 - (x % 1 * 2 - 1).abs()) * 2 - 1;

// ── Timeline ─────────────────────────────────────────────────────────
// Times are seconds of content (the video minus its holds, see
// _contentAt); positions are fractions of the video frame (the phone's own
// screen, scaled). The parts, as cut from the recordings (see the
// scratchpad's make_tutorial.sh):
//   0–7       dropping the first items (Beach, empty table)
//   7–13      three merges: lemons → rum, mints, vodkas
//   13–19     a still of the table; the chain is drawn over it
//   19–23     a crowded table (still); the line is drawn over it
//   23–26.5   opening the Cocktail Menu and picking a Kir Royale
//   26.5–48.9 the button tour (still)

/// The video freezes for two seconds at each of these moments — each
/// placed where the table is still, not mid-fall, so sometimes a little
/// before a caption changes. Baked in by make_tutorial.sh (BOUNDS).
const _holdsAt = [5.75, 12.40, 19.0, 23.0, 26.25, 29.3, 32.1, 34.9, 37.7, 40.5, 43.3, 46.1];

/// The frame each part (content between holds) starts at in the video,
/// measured from the rendered file — the cuts round to whole frames, so
/// these drift a frame or two from a plain sum.
const _partStartFrames = [0, 233, 493, 751, 931, 1089, 1242, 1386, 1530, 1674, 1818, 1962, 2106];

double _contentAt(double video) {
  final frame = video * 30;
  var i = _partStartFrames.lastIndexWhere((f) => f <= frame);
  if (i < 0) i = 0;
  final start = i == 0 ? 0.0 : _holdsAt[i - 1];
  final local = (frame - _partStartFrames[i]) / 30;
  if (i < _holdsAt.length && start + local >= _holdsAt[i]) {
    // In the hold: still the end of this part, not the start of the next
    // (else the next part's overlays — the red line — show early).
    return _holdsAt[i] - 0.001;
  }
  return start + local;
}

/// The video time content time [content] plays at.
double _videoAt(double content) {
  var i = _holdsAt.lastIndexWhere((h) => h <= content) + 1;
  if (i >= _partStartFrames.length) i = _partStartFrames.length - 1;
  final start = i == 0 ? 0.0 : _holdsAt[i - 1];
  return _partStartFrames[i] / 30 + (content - start);
}

const _chainStart = 13.0, _chainEnd = 19.0, _chainStepEvery = 0.38;
const _lineStart = 19.0, _lineEnd = 23.0;
const _lineY = 0.776, _lineLeft = 0.04, _lineRight = 0.957;

typedef _Caption = ({double start, double end, String title, String text});

const List<_Caption> _captions = [
  (start: 0, end: 7, title: 'guide_drop_title', text: 'guide_drop_text'),
  (start: 7, end: 13, title: 'guide_merge_title', text: 'guide_merge_text'),
  (start: 13, end: 19, title: 'guide_chain_title', text: 'guide_chain_text'),
  (start: 19, end: 23, title: 'guide_line_title', text: 'guide_line_text'),
  (start: 23, end: 26.5, title: 'guide_menu_title', text: 'guide_menu_text'),
  (start: 26.5, end: 29.3, title: 'guide_credits_title', text: 'guide_credits_text'),
  (start: 29.3, end: 32.1, title: 'guide_logo_title', text: 'guide_logo_text'),
  (start: 32.1, end: 34.9, title: 'cherry_bomb_label', text: 'guide_bomb_text'),
  (start: 34.9, end: 37.7, title: 'shake_label', text: 'guide_shake_text'),
  (start: 37.7, end: 40.5, title: 'mega_shake_label', text: 'guide_mega_text'),
  (start: 40.5, end: 43.3, title: 'mini_shots_label', text: 'guide_slam_text'),
  (start: 43.3, end: 46.1, title: 'guide_menu_title', text: 'guide_menu_text'),
  (start: 46.1, end: 99, title: 'guide_level_title', text: 'guide_level_text'),
];

_Caption? _captionAt(double t) {
  for (final c in _captions) {
    if (t >= c.start && t < c.end) return c;
  }
  return null;
}

typedef _Highlight = ({double start, double end, Rect rect, bool circle});

const List<_Highlight> _highlights = [
  // The three merges — a pulsing ring where each pair meets.
  (start: 8.3, end: 9.6, rect: Rect.fromLTRB(0.298, 0.345, 0.468, 0.421), circle: true), // lemons
  (start: 10.2, end: 11.4, rect: Rect.fromLTRB(0.510, 0.345, 0.680, 0.421), circle: true), // mints
  (start: 11.6, end: 12.9, rect: Rect.fromLTRB(0.396, 0.345, 0.566, 0.421), circle: true), // vodkas
  // The button tour — each outlined from when the hand arrives until its
  // part ends (through the hold).
  (start: 27.0, end: 29.3, rect: Rect.fromLTRB(0.04, 0.018, 0.32, 0.062), circle: false), // credits
  (start: 29.8, end: 32.1, rect: Rect.fromLTRB(0.36, 0.04, 0.64, 0.10), circle: false), // logo
  (start: 32.6, end: 34.9, rect: Rect.fromLTRB(0.07, 0.125, 0.235, 0.21), circle: false), // bomb
  (start: 35.4, end: 37.7, rect: Rect.fromLTRB(0.245, 0.125, 0.405, 0.21), circle: false), // shake
  (start: 38.2, end: 40.5, rect: Rect.fromLTRB(0.42, 0.118, 0.58, 0.21), circle: false), // mega-shake
  (start: 41.0, end: 43.3, rect: Rect.fromLTRB(0.595, 0.125, 0.755, 0.21), circle: false), // slam mini-shots
  (start: 43.8, end: 46.1, rect: Rect.fromLTRB(0.765, 0.125, 0.93, 0.205), circle: false), // menu
  (start: 46.6, end: 48.9, rect: Rect.fromLTRB(0.02, 0.233, 0.975, 0.298), circle: false), // the 8 tabs
];

/// One hand keyframe: where the fingertip is, whether it's pressing, and
/// whether it's showing (it only fades in at the very start).
typedef _Key = ({double t, double x, double y, bool down, bool shown});

_Key _k(double t, double x, double y, {bool down = false, bool shown = true}) =>
    (t: t, x: x, y: y, down: down, shown: shown);

/// A drag: the waiting item's x (in 1008-wide screen pixels), tracked
/// every 0.1s from the recording; the finger sits just below it.
List<_Key> _drag(double start, List<int> xs, double y) => [
      for (var i = 0; i < xs.length; i++) _k(start + i * 0.1, xs[i] / 1008, y, down: true),
    ];

/// Where the hand waits while the table plays out on its own — the
/// table's near right corner, out of the way.
const _restX = 0.82, _restY = 0.90;
const _dropY = 0.86;

/// One continuous hand: it only fades in at the very start, and only ever
/// travels between parts once the next part has begun (never through a
/// hold, which froze it half-way across the screen); during gameplay it
/// follows the finger's tracked path.
final List<_Key> _hand = [
  // Drop: the mint, dragged left then right, and let go…
  _k(0.0, 0.62, 0.92, shown: false),
  _k(0.5, 0.62, 0.92),
  _k(1.3, 0.50, 0.845),
  _k(1.45, 0.50, 0.845, down: true),
  ..._drag(1.5, const [502, 402, 328, 258, 218, 185, 172, 169, 190, 214, 264, 344, 395, 441, 475, 509, 532, 557, 592, 677, 737, 760, 760, 759], 0.845),
  _k(3.9, 0.753, 0.845),
  // …then the vodka glass.
  _k(4.4, 0.636, 0.871),
  _k(4.75, 0.636, 0.871, down: true),
  ..._drag(4.9, const [594, 529, 496, 487, 474, 399, 356, 277, 230, 239, 279, 355, 393, 416, 433], 0.871),
  _k(6.4, 0.43, 0.871),
  // Merges: four drops, tracked from the recording (the merges themselves
  // are ringed — see _highlights).
  _k(6.9, 0.368, _dropY),
  _k(6.95, 0.368, _dropY, down: true),
  ..._drag(7.0, const [371, 386, 393, 386, 365, 356, 351, 348, 337, 333, 328], _dropY),
  _k(8.15, 0.325, _dropY),
  _k(8.95, 0.318, _dropY),
  _k(9.05, 0.318, _dropY, down: true),
  ..._drag(9.1, const [321, 360, 416, 447, 477, 503, 521, 521], _dropY),
  _k(9.95, 0.517, _dropY),
  _k(10.3, 0.536, _dropY),
  _k(10.35, 0.536, _dropY, down: true),
  ..._drag(10.4, const [540, 565, 566, 566, 552, 531, 485, 459, 439, 426], _dropY),
  _k(11.45, 0.42, _dropY),
  _k(11.6, 0.434, _dropY),
  _k(11.65, 0.434, _dropY, down: true),
  ..._drag(11.7, const [437, 452, 455, 455, 455, 417, 521, 589, 543], _dropY),
  _k(12.65, 0.54, _dropY),
  // The chain plays out; the hand waits at the corner.
  _k(13.5, _restX, _restY),
  _k(19.0, _restX, _restY),
  // Points up at the line.
  _k(19.6, 0.5, 0.82),
  _k(23.0, 0.5, 0.82),
  // The Menu part: up to Menu, tap; across to the Kir Royale, tap.
  _k(23.45, 0.846, 0.175),
  _k(23.6, 0.846, 0.175, down: true),
  _k(23.85, 0.846, 0.175),
  _k(25.25, 0.423, 0.353),
  _k(25.45, 0.423, 0.353, down: true),
  _k(25.8, 0.423, 0.353),
  _k(26.5, 0.423, 0.353),
  // Button tour: each stop held to the end of its part, then on to the
  // next: the credits, the logo, the four power-ups, Menu, then along the
  // tabs.
  _k(27.1, 0.18, 0.045),
  _k(29.3, 0.18, 0.045),
  _k(29.9, 0.50, 0.075),
  _k(32.1, 0.50, 0.075),
  _k(32.7, 0.151, 0.172),
  _k(34.9, 0.151, 0.172),
  _k(35.5, 0.325, 0.172),
  _k(37.7, 0.325, 0.172),
  _k(38.3, 0.50, 0.172),
  _k(40.5, 0.50, 0.172),
  _k(41.1, 0.673, 0.172),
  _k(43.3, 0.673, 0.172),
  _k(43.9, 0.846, 0.172),
  _k(46.1, 0.846, 0.172),
  _k(46.7, 0.08, 0.27),
  _k(48.3, 0.91, 0.27),
  _k(48.9, 0.91, 0.27),
];

({double x, double y, bool down, double opacity})? _handAt(double t) {
  if (t < _hand.first.t) return null;
  if (t >= _hand.last.t) {
    final k = _hand.last;
    return (x: k.x, y: k.y, down: false, opacity: 1);
  }
  for (var i = 0; i < _hand.length - 1; i++) {
    final a = _hand[i], b = _hand[i + 1];
    if (t < a.t || t > b.t) continue;
    final f = b.t == a.t ? 0.0 : Curves.easeInOut.transform((t - a.t) / (b.t - a.t));
    final opacity = (a.shown ? 1.0 : 0.0) + ((b.shown ? 1.0 : 0.0) - (a.shown ? 1.0 : 0.0)) * f;
    return (
      x: a.x + (b.x - a.x) * f,
      y: a.y + (b.y - a.y) * f,
      down: a.down && b.down || (a.down && f < 0.5) || (b.down && f >= 0.5),
      opacity: opacity,
    );
  }
  return null;
}
