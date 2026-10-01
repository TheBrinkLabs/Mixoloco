import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/audio_settings_provider.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/theme/colorful_plank_text.dart';
import '../../../core/widgets/bar_backdrop.dart';
import '../../../core/widgets/wood_plank.dart';

/// Every music track in the game, across all three levels' playlists —
/// just for browsing/previewing here, not tied to which level's
/// actually unlocked.
final kAllSongs = [...kMusicTracks, ...kMusicTracksLevel2, ...kMusicTracksLevel3];

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
/// (restored on exit) so a preview never plays over it.
class SongsScreen extends ConsumerStatefulWidget {
  const SongsScreen({super.key});

  @override
  ConsumerState<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends ConsumerState<SongsScreen> {
  AudioPlayer? _player;
  String? _playingFile;

  @override
  void initState() {
    super.initState();
    ref.read(audioSettingsProvider.notifier).stopMusic();
  }

  @override
  void dispose() {
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
      body: BarBackdrop(
        showTable: false,
        showHeaderBoard: false,
        child: Stack(
          children: [
            Positioned(left: 12, top: 10, child: PlankBackButton(onTap: () => Navigator.of(context).pop())),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WoodTitlePlank(title: tr(locale, 'songs'), icon: Icons.music_note_rounded, width: plankWidth, height: plankHeight, assetPath: 'assets/images/menu_board_3.png'),
                    for (final file in kAllSongs)
                      _SongRow(file: file, playing: _playingFile == file, onTap: () => _toggle(file), width: plankWidth, height: plankHeight),
                  ],
                ),
              ),
            ),
          ],
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
