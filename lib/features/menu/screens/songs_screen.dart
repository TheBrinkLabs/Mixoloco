import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/audio_settings_provider.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/theme/colorful_plank_text.dart';
import '../../../core/widgets/bar_backdrop.dart';
import '../../../core/widgets/wood_plank.dart';
import '../info_level_data.dart';

/// A song's display name — its filename, minus the extension, with
/// underscores swapped for spaces (per feedback: "the filename without
/// the _").
String songDisplayName(String file) {
  final dot = file.lastIndexOf('.');
  final base = dot >= 0 ? file.substring(0, dot) : file;
  return base.replaceAll('_', ' ');
}

/// Lets the player preview any track in the game on its own, outside of
/// whichever playlist is actually driving the background music right
/// now. Mutes the real menu/game bgm for as long as this screen is open
/// (restored on exit) so a preview never plays over it. Same swipe-
/// between-levels pattern as ingredients_screen.dart/
/// cocktails_screen.dart — each level's own page lists just that
/// level's playlist against that level's own backdrop, rather than one
/// flat list of every track in the game with no sense of which bar it
/// belongs to. Playback state lives here (not per-page) since only one
/// preview should ever play regardless of which page it was started
/// from, and swiping to another page shouldn't stop it.
class SongsScreen extends ConsumerStatefulWidget {
  const SongsScreen({super.key});

  @override
  ConsumerState<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends ConsumerState<SongsScreen> {
  final _pageController = PageController();
  AudioPlayer? _player;
  String? _playingFile;

  @override
  void initState() {
    super.initState();
    ref.read(audioSettingsProvider.notifier).stopMusic();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _player?.stop();
    ref.read(audioSettingsProvider.notifier).playMenuMusic();
    super.dispose();
  }

  Future<void> _toggle(String file) async {
    final previous = _player;
    _player = null;
    await previous?.stop();
    if (_playingFile == file) {
      setState(() => _playingFile = null);
      return;
    }
    setState(() => _playingFile = file);
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
    player.onPlayerComplete.listen((_) {
      if (mounted && _playingFile == file) setState(() => _playingFile = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final screenSize = MediaQuery.sizeOf(context);
    const sideMargin = 28.0;
    final plankWidth = screenSize.width - sideMargin * 2;
    final plankHeight = plankWidth / kMenuBoard3Aspect;

    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            children: [
              for (final level in kInfoLevels)
                _SongsLevelPage(
                  level: level,
                  plankWidth: plankWidth,
                  plankHeight: plankHeight,
                  locale: locale,
                  playingFile: _playingFile,
                  onToggle: _toggle,
                ),
            ],
          ),
          // Painted last — see info_screen.dart's matching comment.
          Positioned(left: 12, top: 10, child: PlankBackButton(onTap: () => Navigator.of(context).pop())),
        ],
      ),
    );
  }
}

class _SongsLevelPage extends StatelessWidget {
  final InfoLevelData level;
  final double plankWidth;
  final double plankHeight;
  final AppLocale locale;
  final String? playingFile;
  final ValueChanged<String> onToggle;
  const _SongsLevelPage({
    required this.level,
    required this.plankWidth,
    required this.plankHeight,
    required this.locale,
    required this.playingFile,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return BarBackdrop(
      showTable: false,
      showHeaderBoard: false,
      backgroundAssetPath: level.backgroundAssetPath,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WoodTitlePlank(
                title: '${tr(locale, 'songs')} — ${level.name}',
                icon: Icons.music_note_rounded,
                iconAsset: 'assets/images/play.png',
                width: plankWidth,
                height: plankHeight,
                assetPath: 'assets/images/menu_board_3.png',
                fontScale: 0.72,
              ),
              for (final file in level.songs)
                _SongRow(file: file, playing: playingFile == file, onTap: () => onToggle(file), width: plankWidth, height: plankHeight),
            ],
          ),
        ),
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  final String file;
  final bool playing;
  final VoidCallback onTap;
  final double width;
  final double height;
  const _SongRow({required this.file, required this.playing, required this.onTap, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: WoodPlank(
        width: width,
        height: height,
        assetPath: 'assets/images/menu_board_3.png',
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: width * 0.06),
          child: Row(
            children: [
              Expanded(
                child: ColorfulPlankText(text: songDisplayName(file), fontSize: height * 0.2, variant: kPlankTextVariant, font: kPlankTextFont, shadowStyle: kPlankShadowStyle),
              ),
              SizedBox(width: width * 0.03),
              playing
                  ? Icon(Icons.pause_circle_filled_rounded, size: height * 0.52, color: kPlankIconColor, shadows: kPlankIconShadows)
                  : Image.asset('assets/images/play_button.png', width: height * 0.52, height: height * 0.52, fit: BoxFit.contain),
            ],
          ),
        ),
      ),
    );
  }
}
