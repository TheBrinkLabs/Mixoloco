import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/progression_service.dart';

/// Whether cocktails drive progression — on by default (the game's
/// normal mode). See [loadCocktailModeEnabled]'s doc for what turning
/// it off actually changes.
class CocktailModeNotifier extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return true;
  }

  Future<void> _load() async {
    state = await loadCocktailModeEnabled();
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await saveCocktailModeEnabled(enabled);
  }
}

final cocktailModeProvider = NotifierProvider<CocktailModeNotifier, bool>(CocktailModeNotifier.new);
