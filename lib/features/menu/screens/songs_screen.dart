import 'dart:async';
import 'dart:math';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/audio_settings_provider.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/services/share_service.dart';
import '../../../core/widgets/bar_backdrop.dart';
import '../../../core/widgets/submenu_kit.dart';
import '../../../data/models/ingredient.dart' show isAfterDarkLevel;
import '../../game/providers/game_state_provider.dart';
import '../info_level_data.dart';

/// A song's display name — its filename, minus the extension, with
/// underscores swapped for spaces (per feedback: "the filename without
/// the _").
String songDisplayName(String file) {
  final dot = file.lastIndexOf('.');
  final base = dot >= 0 ? file.substring(0, dot) : file;
  return base.replaceAll('_', ' ');
}

/// off: stop when the queue runs out. all: wrap back to the first track.
/// one: keep replaying whatever's currently playing, ignoring the queue.
enum _RepeatMode { off, all, one }

/// Lets the player preview any track in the game on its own, outside of
/// whichever playlist is actually driving the background music right
/// now. Mutes the real menu/game bgm for as long as this screen is open
/// (restored on exit) so a preview never plays over it. `LevelPager`
/// handles whether a level's own page is reachable at all
/// (`highestLevelReached`); within a reached page, a level's songs are
/// still shown locked until the player's made at least one merge there
/// (`highestTierFor(...) >= 0`, per the confirmed "whole level
/// unlocks together" rule) — see screenshot 08 in the design handoff,
/// where a reached-but-unplayed level shows its pager and count row
/// normally but every row is still a `???` silhouette. Playback state
/// lives here (not per-row) since only one preview should ever play
/// regardless of which page it was started from, and swiping to
/// another page shouldn't stop it.
///
/// Real per-track durations aren't part of the game's data model (the
/// handoff's own durations are explicitly placeholder numbers) and
/// probing every track's length up front isn't worth the extra
/// AudioPlayer instances/platform risk just for a cosmetic label, so
/// the idle row simply has no duration text — unlike the handoff mock.
class SongsScreen extends ConsumerStatefulWidget {
  const SongsScreen({super.key});

  @override
  ConsumerState<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends ConsumerState<SongsScreen> {
  AudioPlayer? _player;
  String? _playingFile;
  Duration _position = Duration.zero;
  Duration? _duration;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<void>? _completeSub;

  /// Set while a "Play All" run is in progress — the level's own song
  /// list, in order. [_onTrackComplete] advances through it; any manual
  /// row tap ([_toggle]) clears it, since a direct pick breaks out of
  /// the auto-advancing sequence.
  List<String>? _playAllQueue;

  /// Tracks which level's page is currently swiped into view, so the
  /// screen's own backdrop photo (see SubmenuScaffold.backgroundAssetPath)
  /// follows along rather than staying fixed on the beach.
  late int _levelIndex;

  bool _shuffleEnabled = false;

  /// A frozen shuffled copy of [_playAllQueue], rolled fresh each time
  /// shuffle is toggled on so a tap doesn't reshuffle mid-queue — cleared
  /// when shuffle is toggled off or the queue itself ends.
  List<String>? _shuffledOrder;

  _RepeatMode _repeatMode = _RepeatMode.off;

  /// Collapses the panel down to just a slim now-playing bar — see
  /// [_buildMinimized].
  bool _minimized = false;

  /// Captured in initState — Riverpod 3 throws if ref is used in dispose().
  late final AudioSettingsNotifier _audio;

  @override
  void initState() {
    super.initState();
    final board = ref.read(gameStateProvider);
    _levelIndex = (board.highestLevelReached - 1).clamp(0, kInfoLevels.length - 1);
    _audio = ref.read(audioSettingsProvider.notifier);
    _audio.stopMusic();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    _player?.stop();
    _audio.playMenuMusic();
    super.dispose();
  }

  Future<void> _stopPlayback() async {
    final previous = _player;
    _player = null;
    await _posSub?.cancel();
    await _durSub?.cancel();
    await _completeSub?.cancel();
    await previous?.stop();
  }

  Future<void> _toggle(String file) async {
    _playAllQueue = null;
    if (_playingFile == file) {
      await _stopPlayback();
      if (mounted) setState(() => _playingFile = null);
      return;
    }
    await _stopPlayback();
    await _playFile(file);
  }

  /// Plays every song in [songs] (a level's full list, in order) back to
  /// back — advancing automatically on each one's natural completion,
  /// see [_onTrackComplete].
  Future<void> _playAll(List<String> songs) async {
    if (songs.isEmpty) return;
    await _stopPlayback();
    _playAllQueue = songs;
    await _playFile(songs.first);
  }

  Future<void> _playFile(String file) async {
    setState(() {
      _playingFile = file;
      _position = Duration.zero;
      _duration = null;
    });
    final player = await FlameAudio.playLongAudio(file, volume: 0.7);
    if (!mounted) {
      await player.stop();
      return;
    }
    // Bailed out already (another track tapped while this one was still
    // loading) — don't let a late-arriving player start playing over it.
    if (_playingFile != file) {
      await player.stop();
      return;
    }
    _player = player;
    _posSub = player.onPositionChanged.listen((d) {
      if (mounted) setState(() => _position = d);
    });
    _durSub = player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _completeSub = player.onPlayerComplete.listen((_) => _onTrackComplete(file));
    // onDurationChanged is a one-shot event fired as soon as the source's
    // duration is known — for a local asset that's essentially immediate,
    // during play()'s own setSource() call, which happens *before*
    // playLongAudio ever returns control to us. By the time the listener
    // above is attached, that single event has already fired into the
    // void, so the stream alone leaves _duration (and the progress bar)
    // stuck at null/0 forever. Ask for it directly instead, which queries
    // the player's current state rather than waiting on a push that's
    // already happened.
    player.getDuration().then((d) {
      if (mounted && _playingFile == file && d != null) setState(() => _duration = d);
    });
  }

  void _onTrackComplete(String file) {
    if (!mounted || _playingFile != file) return;
    final queue = _playAllQueue;
    if (queue == null) {
      setState(() => _playingFile = null);
      return;
    }
    if (_repeatMode == _RepeatMode.one) {
      _playFile(file);
      return;
    }
    final order = _shuffleEnabled ? (_shuffledOrder ??= ([...queue]..shuffle())) : queue;
    final next = order.indexOf(file) + 1;
    if (next > 0 && next < order.length) {
      _playFile(order[next]);
      return;
    }
    if (_repeatMode == _RepeatMode.all) {
      _playFile(order.first);
      return;
    }
    setState(() {
      _playingFile = null;
      _playAllQueue = null;
      _shuffledOrder = null;
    });
  }

  void _toggleShuffle(List<String> queue) {
    setState(() {
      _shuffleEnabled = !_shuffleEnabled;
      _shuffledOrder = _shuffleEnabled ? ([...queue]..shuffle()) : null;
    });
  }

  void _cycleRepeat() {
    setState(() {
      _repeatMode = switch (_repeatMode) {
        _RepeatMode.off => _RepeatMode.all,
        _RepeatMode.all => _RepeatMode.one,
        _RepeatMode.one => _RepeatMode.off,
      };
    });
  }

  /// Steps the active Play-All queue forward/back by one — shared by the
  /// minimized player bar's prev/next buttons. No-ops when nothing's
  /// queued (a single row tapped directly via [_toggle], not Play All).
  void _skip(int direction) {
    final queue = _playAllQueue;
    final file = _playingFile;
    if (queue == null || file == null) return;
    final order = _shuffleEnabled ? (_shuffledOrder ??= ([...queue]..shuffle())) : queue;
    final idx = order.indexOf(file);
    if (idx == -1) return;
    _playFile(order[(idx + direction + order.length) % order.length]);
  }

  @override
  Widget build(BuildContext context) {
    if (_minimized) return _buildMinimized(context);

    final locale = ref.watch(localeProvider);
    final board = ref.watch(gameStateProvider);

    int bucketFor(int level) => guideTierFor(board.highestTiers, level);

    // Matches SubmenuScaffold's own ribbonTop default (not overridden
    // below) — kept as a local constant so the toggle button can line up
    // level with the ribbon title, per feedback, rather than sitting up
    // by the back button.
    const ribbonTop = 122.0;
    final screenWidth = MediaQuery.sizeOf(context).width;

    // The toggle needs to sit visually in front of the ribbon (overlapping
    // its right edge), not just beside it — SubmenuScaffold's own
    // `aboveRibbon` slot paints *behind* the ribbon, so it can't be used
    // here; this wraps the whole scaffold in one more Stack with the
    // button as the topmost layer instead.
    return Stack(
      children: [
        SubmenuScaffold(
          title: tr(locale, 'songs'),
          panelBottom: 86,
          backgroundAssetPath: backgroundAssetPathForLevel(kInfoLevels[_levelIndex].level),
          night: isAfterDarkLevel(kInfoLevels[_levelIndex].level),
          child: LevelPager(
            itemCount: kInfoLevels.length,
            initialPage: (board.highestLevelReached - 1).clamp(0, kInfoLevels.length - 1),
            levelName: (i) => kInfoLevels[i].name,
            levelReached: (i) => guideLevelReached(kInfoLevels[i].level, board.highestLevelReached),
            lockedNoun: tr(locale, 'songs').toLowerCase(),
            onPageChanged: (i) => setState(() => _levelIndex = i),
            pageBuilder: (context, i) {
              final level = kInfoLevels[i];
              final unlocked = bucketFor(level.level) >= 0;
              // A daytime bar's fourth track stays locked until its After
              // Dark level is reached, even once the rest of the page is.
              final bonus = level.bonusSong;
              final bonusUnlocked = bonus != null && unlocked && guideLevelReached(level.bonusSongLevel!, board.highestLevelReached);
              final songs = [...level.songs, if (bonusUnlocked) bonus];
              final totalCount = level.songs.length + (bonus == null ? 0 : 1);
              final unlockedCount = unlocked ? songs.length : 0;
              final playingThisQueue = _playingFile != null && listEquals(_playAllQueue, songs);
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CountRow(label: tr(locale, 'unlocked_label'), value: '$unlockedCount / $totalCount'),
                    const SizedBox(height: 10),
                    if (unlocked) ...[
                      Row(
                        children: [
                          _PlayAllIconButton(
                            playing: playingThisQueue,
                            onTap: playingThisQueue ? () => _toggle(_playingFile!) : () => _playAll(songs),
                          ),
                          const Spacer(),
                          _ShuffleButton(enabled: _shuffleEnabled, onTap: () => _toggleShuffle(songs)),
                          const SizedBox(width: 8),
                          _RepeatButton(mode: _repeatMode, onTap: _cycleRepeat),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    for (final file in [...level.songs, ?bonus])
                      Padding(
                        padding: EdgeInsets.only(bottom: file == (bonus ?? level.songs.last) ? 0 : 8),
                        child: _SongRow(
                          file: file,
                          locked: !songs.contains(file) || !unlocked,
                          lockedHint: file == bonus && unlocked && !bonusUnlocked
                              ? tr(locale, 'unlocks_at_level').replaceFirst('{n}', '${level.bonusSongLevel}')
                              : null,
                          playing: _playingFile == file,
                          position: _position,
                          duration: _duration,
                          onTap: unlocked && songs.contains(file) ? () => _toggle(file) : null,
                          onShare: () => shareText(tr(locale, 'share_song_text').replaceFirst('{song}', songDisplayName(file))),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        Positioned(
          left: screenWidth / 2 + 50,
          top: ribbonTop + 5,
          child: GoldArrowButton(
            icon: Icons.keyboard_arrow_down_rounded,
            enabled: true,
            onTap: () => setState(() => _minimized = true),
            size: 40,
          ),
        ),
      ],
    );
  }

  /// Bypasses SubmenuScaffold entirely rather than just swapping its
  /// child — SubmenuScaffold always pins both the panel's top and bottom,
  /// so a smaller child wouldn't actually shrink the painted panel, just
  /// leave it mostly empty. Composed directly on the same primitives
  /// (BarBackdrop/SubmenuToneGradient/SubmenuBackButton) instead, with
  /// just a slim now-playing bar at the bottom.
  Widget _buildMinimized(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: BarBackdrop(
        showTable: false,
        backgroundAssetPath: backgroundAssetPathForLevel(kInfoLevels[_levelIndex].level),
        night: isAfterDarkLevel(kInfoLevels[_levelIndex].level),
        child: Stack(
          children: [
            const Positioned.fill(child: SubmenuToneGradient()),
            Positioned(
              left: 20,
              top: 10 + topInset,
              child: SubmenuBackButton(onTap: () => Navigator.of(context).pop()),
            ),
            Positioned(
              right: 20,
              top: 10 + topInset,
              child: GoldArrowButton(
                icon: Icons.keyboard_arrow_up_rounded,
                enabled: true,
                onTap: () => setState(() => _minimized = false),
                size: 46,
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16 + 86,
              child: _MinimizedPlayerBar(
                file: _playingFile,
                playing: _playingFile != null,
                position: _position,
                duration: _duration,
                canSkip: _playAllQueue != null,
                onPlayPause: _playingFile == null ? null : () => _toggle(_playingFile!),
                onPrevious: () => _skip(-1),
                onNext: () => _skip(1),
                locale: locale,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Starts (or stops) a sequential run through every song on the current
/// level's page — see [_SongsScreenState._playAll]/[_onTrackComplete].
/// Shrunk to an icon-only circle (was a full-width labeled pill) so
/// shuffle/repeat can share the same row, per feedback.
class _PlayAllIconButton extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;
  const _PlayAllIconButton({required this.playing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: playing ? SubmenuColors.greenEdge : SubmenuColors.goldEdge, width: 2),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: playing ? const [Color(0xFF9CF06A), Color(0xFF2F9E27)] : const [SubmenuColors.goldTop, SubmenuColors.goldBottom],
          ),
          boxShadow: [BoxShadow(color: playing ? SubmenuColors.greenEdge : SubmenuColors.goldEdge, offset: const Offset(0, 3))],
        ),
        child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 22),
      ),
    );
  }
}

/// Dimmed gold when off, bright gold when on — same circular chrome as
/// [_PlayButton]'s idle state.
class _ShuffleButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _ShuffleButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: enabled ? SubmenuColors.gold : SubmenuColors.toggleOffBorder, width: 2),
          color: enabled ? SubmenuColors.goldBottom : SubmenuColors.toggleOffTrack,
        ),
        child: Icon(Icons.shuffle_rounded, color: enabled ? Colors.white : SubmenuColors.textDisabled, size: 18),
      ),
    );
  }
}

/// Cycles off -> all -> one -> off on tap; swaps icon for repeat-one's
/// own glyph rather than just recolouring the same one, so the mode
/// reads clearly at a glance.
class _RepeatButton extends StatelessWidget {
  final _RepeatMode mode;
  final VoidCallback onTap;
  const _RepeatButton({required this.mode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = mode != _RepeatMode.off;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: active ? SubmenuColors.gold : SubmenuColors.toggleOffBorder, width: 2),
          color: active ? SubmenuColors.goldBottom : SubmenuColors.toggleOffTrack,
        ),
        child: Icon(
          mode == _RepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
          color: active ? Colors.white : SubmenuColors.textDisabled,
          size: 18,
        ),
      ),
    );
  }
}

/// The minimized view's slim now-playing bar — reuses [_SongRow]'s own
/// playing-state visuals (progress bar, [_Equalizer]) just transplanted
/// into a short fixed-height container, plus prev/next controls walking
/// the same Play-All queue [_SongsScreenState._skip] does.
class _MinimizedPlayerBar extends StatelessWidget {
  final String? file;
  final bool playing;
  final Duration position;
  final Duration? duration;
  final bool canSkip;
  final VoidCallback? onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final AppLocale locale;
  const _MinimizedPlayerBar({
    required this.file,
    required this.playing,
    required this.position,
    required this.duration,
    required this.canSkip,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (duration != null && duration!.inMilliseconds > 0)
        ? (position.inMilliseconds / duration!.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SubmenuColors.gold, width: 2),
        gradient: playing
            ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2A6AA5), Color(0xFF1D5185)])
            : null,
        color: playing ? null : SubmenuColors.inset,
      ),
      child: Row(
        children: [
          GoldArrowButton(icon: Icons.skip_previous_rounded, enabled: canSkip, onTap: onPrevious, size: 32),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onPlayPause,
            behavior: HitTestBehavior.opaque,
            child: _PlayButton(locked: false, playing: playing),
          ),
          const SizedBox(width: 8),
          GoldArrowButton(icon: Icons.skip_next_rounded, enabled: canSkip, onTap: onNext, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  file == null ? tr(locale, 'songs') : songDisplayName(file!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Lilita One', fontSize: 15, color: Colors.white),
                ),
                if (playing) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      backgroundColor: SubmenuColors.inset,
                      valueColor: const AlwaysStoppedAnimation(SubmenuColors.greenBright),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (playing) ...[const SizedBox(width: 12), const _Equalizer()],
        ],
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  final String file;
  final bool locked;

  /// Shown under a locked row's `???` — e.g. when the bonus track unlocks.
  final String? lockedHint;
  final bool playing;
  final Duration position;
  final Duration? duration;
  final VoidCallback? onTap;
  final VoidCallback onShare;
  const _SongRow({
    required this.file,
    required this.locked,
    this.lockedHint,
    required this.playing,
    required this.position,
    required this.duration,
    required this.onTap,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (duration != null && duration!.inMilliseconds > 0)
        ? (position.inMilliseconds / duration!.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 90),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SubmenuColors.gold, width: 2),
          color: playing ? null : (locked ? SubmenuColors.lockedCard.withValues(alpha: 0.6) : SubmenuColors.inset),
          gradient: playing
              ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2A6AA5), Color(0xFF1D5185)])
              : null,
        ),
        child: Row(
          children: [
            _PlayButton(locked: locked, playing: playing),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    locked ? '???' : songDisplayName(file),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Lilita One',
                      fontSize: 18,
                      color: locked ? SubmenuColors.textDisabled : Colors.white,
                    ),
                  ),
                  if (locked && lockedHint != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      lockedHint!,
                      style: submenuNunito(size: 12, weight: FontWeight.w800, color: SubmenuColors.textSecondary),
                    ),
                  ],
                  if (playing) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        backgroundColor: SubmenuColors.inset,
                        valueColor: const AlwaysStoppedAnimation(SubmenuColors.greenBright),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (playing) ...[
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: onShare,
                    behavior: HitTestBehavior.opaque,
                    child: const Icon(Icons.share_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(height: 6),
                  const _Equalizer(),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool locked;
  final bool playing;
  const _PlayButton({required this.locked, required this.playing});

  @override
  Widget build(BuildContext context) {
    if (locked) {
      return Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1A3A5A)),
        child: const Icon(Icons.lock_rounded, color: SubmenuColors.textDisabled, size: 18),
      );
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: playing ? SubmenuColors.greenEdge : SubmenuColors.goldEdge, width: 2),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: playing ? const [Color(0xFF9CF06A), Color(0xFF2F9E27)] : const [SubmenuColors.goldTop, SubmenuColors.goldBottom],
        ),
        boxShadow: [BoxShadow(color: playing ? SubmenuColors.greenEdge : SubmenuColors.goldEdge, offset: const Offset(0, 3))],
      ),
      child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 20),
    );
  }
}

/// The small 4-bar "now playing" equalizer, animated heights looping on
/// a stagger — replaces the idle duration text while a track plays.
class _Equalizer extends StatefulWidget {
  const _Equalizer();

  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const phases = [0.0, 0.2, 0.45, 0.7];
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          height: 20,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final phase in phases) ...[
                if (phase != phases.first) const SizedBox(width: 3),
                Container(
                  width: 4,
                  height: 8 + 12 * (0.5 + 0.5 * sin(2 * pi * (_controller.value + phase))),
                  decoration: BoxDecoration(color: SubmenuColors.greenBright, borderRadius: BorderRadius.circular(2)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
