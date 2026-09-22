import 'dart:async';
import 'dart:math';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/progression_service.dart';

/// Background music tracks, played one after the other on repeat (not
/// looping a single track) — relative to FlameAudio's default
/// 'assets/audio/' prefix. Playback starts on a random track each app
/// launch (see AudioSettingsNotifier._trackIndex's initializer) rather
/// than always opening on the first one.
const kMusicTracks = ['Saltwater_Morning.mp3', 'Saltwater_Sunsets.mp3', 'Warm_Afternoon_Tide.mp3'];

/// The rooftop bar's own playlist (Level 2) — swapped in by
/// [AudioSettingsNotifier.playGameMusic]'s `rooftop` flag once
/// GameScreen's own background has switched to rooftop_background.png.
/// Menu music stays on [kMusicTracks] regardless of lifetime level
/// reached — the home screen's own visuals (sign, sand, boards) never
/// change, only the in-game table does.
const kMusicTracksLevel2 = ['Amber_Glass_and_Velvet.mp3', 'Velvet_Boulevard.mp3', 'Velvet_Strings_at_Dusk.mp3'];

class AudioSettings {
  final bool menuMusicEnabled;
  final bool gameMusicEnabled;
  final bool sfxEnabled;

  const AudioSettings({required this.menuMusicEnabled, required this.gameMusicEnabled, required this.sfxEnabled});

  AudioSettings copyWith({bool? menuMusicEnabled, bool? gameMusicEnabled, bool? sfxEnabled}) => AudioSettings(
    menuMusicEnabled: menuMusicEnabled ?? this.menuMusicEnabled,
    gameMusicEnabled: gameMusicEnabled ?? this.gameMusicEnabled,
    sfxEnabled: sfxEnabled ?? this.sfxEnabled,
  );
}

/// Owns both the persisted audio settings and the actual music playlist
/// playback — menu and game screens each call [playMenuMusic]/
/// [playGameMusic] on entry and [stopMusic] on exit, and this decides
/// whether that's actually allowed and whether playback needs to
/// start/keep going. A single shared player/playlist position means
/// music started on the menu keeps playing uninterrupted into a game (and
/// back) rather than restarting from track one every screen change.
class AudioSettingsNotifier extends Notifier<AudioSettings> {
  // A fresh random pick each time the app process starts (this notifier
  // is recreated then, not on every screen change) rather than always
  // opening on the same track.
  int _trackIndex = Random().nextInt(kMusicTracks.length);
  // Which of the two playlists _trackIndex currently indexes into —
  // switched by playGameMusic's `rooftop` flag once Level 2's reached;
  // playMenuMusic always targets kMusicTracks, since the menu's own
  // visuals never change with level.
  List<String> _activePlaylist = kMusicTracks;
  bool _playlistActive = false;
  StreamSubscription<void>? _completeSub;

  @override
  AudioSettings build() {
    _loadPersisted();
    return const AudioSettings(menuMusicEnabled: true, gameMusicEnabled: true, sfxEnabled: true);
  }

  Future<void> _loadPersisted() async {
    final results = await Future.wait([loadMenuMusicEnabled(), loadGameMusicEnabled(), loadSfxEnabled()]);
    state = AudioSettings(menuMusicEnabled: results[0], gameMusicEnabled: results[1], sfxEnabled: results[2]);
  }

  /// Called from the Settings toggle — also starts/stops playback
  /// immediately, since Settings only ever opens from the menu screen
  /// itself.
  Future<void> setMenuMusicEnabled(bool enabled) async {
    state = state.copyWith(menuMusicEnabled: enabled);
    await saveMenuMusicEnabled(enabled);
    if (enabled) {
      await _startPlaylist(kMusicTracks);
    } else {
      await stopMusic();
    }
  }

  /// Called from the Settings toggle — persists only; there's no live
  /// game session to react to from the menu screen's Settings sheet, it
  /// just applies next time a game is entered.
  Future<void> setGameMusicEnabled(bool enabled) async {
    state = state.copyWith(gameMusicEnabled: enabled);
    await saveGameMusicEnabled(enabled);
  }

  Future<void> setSfxEnabled(bool enabled) async {
    state = state.copyWith(sfxEnabled: enabled);
    await saveSfxEnabled(enabled);
  }

  /// Starts (or keeps playing) the beach playlist if menu music is
  /// enabled — called whenever the menu screen becomes current.
  Future<void> playMenuMusic() async {
    if (!state.menuMusicEnabled) {
      await stopMusic();
      return;
    }
    await _startPlaylist(kMusicTracks);
  }

  /// Starts (or keeps playing) the music playlist if game music is
  /// enabled — called whenever the game screen becomes current, or its
  /// board's own level changes mid-session (leveling up, see
  /// GameScreen._runLevelUp). [rooftop] picks [kMusicTracksLevel2]
  /// instead of the beach playlist once Level 2's been reached.
  Future<void> playGameMusic({bool rooftop = false}) async {
    if (!state.gameMusicEnabled) {
      await stopMusic();
      return;
    }
    await _startPlaylist(rooftop ? kMusicTracksLevel2 : kMusicTracks);
  }

  Future<void> stopMusic() async {
    _playlistActive = false;
    await _completeSub?.cancel();
    _completeSub = null;
    try {
      await FlameAudio.bgm.stop();
    } catch (_) {
      // Soft failure — music is decorative, never block gameplay on it.
    }
  }

  Future<void> _startPlaylist(List<String> playlist) async {
    if (!identical(_activePlaylist, playlist)) {
      // A genuine playlist change (menu <-> game, or beach <-> rooftop
      // mid-session) — always (re)start on a fresh random track from the
      // new list rather than trying to preserve position across two
      // playlists that don't correspond to each other, and force the
      // actual playback restart below regardless of whatever was already
      // playing.
      _activePlaylist = playlist;
      _trackIndex = Random().nextInt(playlist.length);
      _playlistActive = false;
    }
    if (_playlistActive) {
      // Already tracked as active — but backgrounding the app can get the
      // OS/platform player to silently stop actual playback without ever
      // telling this notifier, leaving _playlistActive stale-true and
      // every subsequent playMenuMusic()/playGameMusic() call a no-op
      // (this is exactly what made "leave and come back" require an
      // explicit Settings off/on toggle to fix — that toggle's own
      // stopMusic() call was the only thing that ever reset the flag).
      // audioplayers' own reported state is the real source of truth for
      // whether sound is actually coming out, so check that before
      // trusting the flag.
      try {
        if (FlameAudio.bgm.audioPlayer.state == PlayerState.playing) return;
      } catch (_) {
        return;
      }
    }
    _playlistActive = true;
    try {
      _completeSub ??= FlameAudio.bgm.audioPlayer.onPlayerComplete.listen((_) => _playNextTrack());
      await _playTrack(_trackIndex);
    } catch (_) {
      // Soft failure, same as above.
    }
  }

  Future<void> _playNextTrack() async {
    if (!_playlistActive) return;
    _trackIndex = (_trackIndex + 1) % _activePlaylist.length;
    await _playTrack(_trackIndex);
  }

  Future<void> _playTrack(int index) async {
    try {
      final player = FlameAudio.bgm.audioPlayer;
      await player.setReleaseMode(ReleaseMode.release);
      await player.setVolume(0.5);
      await player.play(AssetSource(_activePlaylist[index]));
    } catch (_) {
      // Soft failure, same as above.
    }
  }
}

final audioSettingsProvider = NotifierProvider<AudioSettingsNotifier, AudioSettings>(AudioSettingsNotifier.new);
