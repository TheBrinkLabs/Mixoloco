import '../services/locale_provider.dart';

/// Every code-rendered piece of UI chrome text in the app, in English and
/// Spanish — cocktail/ingredient names are deliberately left out (proper
/// nouns that read the same, or close enough, in both languages, same as
/// "Mojito" on an English or Spanish-language menu in real life). The
/// five in-game action buttons (Cherry Bomb/Shake/Mega-Shake/Alcohol-
/// Free/Menu) used to be wood signs with their own English text painted
/// in, so needed new art to translate — they're plain photo icons now,
/// with their labels (and costs, where one applies) rendered here
/// instead, so this is the only place that needs touching for those.
///
/// [tr] falls back to the English string (or the raw key, if that's
/// somehow missing too) rather than ever showing a blank — a missing
/// translation should never be worse than the wrong language.
String tr(AppLocale locale, String key) {
  final map = locale == AppLocale.es ? _es : _en;
  return map[key] ?? _en[key] ?? key;
}

const _en = <String, String>{
  'play_game': 'Play Game',
  'best_scores': 'Best Scores',
  'leaderboard': 'Leaderboard',
  'shop': 'Shop',
  'settings': 'Settings',
  'soon': 'SOON',
  'credits': 'Credits',
  'level': 'Level',
  'unlocked': 'Unlocked',
  'music_in_menu': 'Music in Menu',
  'music_in_game': 'Music in Game',
  'sound_effects': 'Sound Effects',
  'language': 'Language',
  'no_scores_yet': 'No scores yet — go play!',
  'score_label': 'Score',
  'cocktail_menu': 'Cocktail Menu',
  'menu_label': 'Menu',
  'cherry_bomb_label': 'Cherry Bomb',
  'shake_label': 'Shake',
  'mega_shake_label': 'Mega-Shake',
  'alcohol_free_label': 'No Alcohol',
  'active': 'ACTIVE',
  'next': 'Next',
  'table_full_banner': "Table's full — that's game over.",
  'table_full_title': "Table's full!",
  'table_full_body': 'Watch an ad to clear all the\nvodka & rum and keep playing?',
  'watch_ad_clear': 'Watch Ad & Clear Shots',
  'end_game': 'End Game',
  'ad_playing': 'Ad playing…',
  'game_over': 'Game Over',
  'cocktails_made_label': 'Cocktails made',
  'play_again': 'Play Again',
  'home': 'Home',
  'ads_consent_title': 'Ads Keep Mixoloco Free',
  'ads_consent_body':
      "We'd like to show ads tailored to you, which helps them pay better. "
      "You'll see ads either way — this just decides whether they're personalized. "
      'You can change your mind anytime.',
  'allow': 'Allow',
  'no_thanks': 'No thanks',
  'advertisement': 'ADVERTISEMENT',
  'continue_label': 'Continue',
  'continue_in': 'Continue in',
  'ad_not_ready': 'Ad not ready — try again in a moment',
  'shop_watch_ad_title': 'Watch an ad for',
  'shop_watch_ad_button': 'Watch Ad',
  'shop_credits_earned': 'Credits earned!',
  'level_complete_title': 'Level Complete!',
  'onto_next_level': 'Onto the next level!',
  'reset_progress': 'Reset Progress',
  'reset_progress_button': 'Reset',
  'reset_progress_confirm_title': 'Reset your progress?',
  'reset_progress_confirm_body': "This puts your evolution and level back to the start. Your credits won't be touched.",
  'cancel': 'Cancel',
};

const _es = <String, String>{
  'play_game': 'Jugar',
  'best_scores': 'Mejores Puntuaciones',
  'leaderboard': 'Clasificación',
  'shop': 'Tienda',
  'settings': 'Ajustes',
  'soon': 'PRONTO',
  'credits': 'Créditos',
  'level': 'Nivel',
  'unlocked': 'Desbloqueado',
  'music_in_menu': 'Música en el Menú',
  'music_in_game': 'Música en el Juego',
  'sound_effects': 'Efectos de Sonido',
  'language': 'Idioma',
  'no_scores_yet': '¡Aún no hay puntuaciones — ve a jugar!',
  'score_label': 'Puntuación',
  'cocktail_menu': 'Menú de Cócteles',
  'menu_label': 'Menú',
  'cherry_bomb_label': 'Bomba de Cereza',
  'shake_label': 'Agitar',
  'mega_shake_label': 'Mega-Agitar',
  'alcohol_free_label': 'Sin Alcohol',
  'active': 'ACTIVO',
  'next': 'Siguiente',
  'table_full_banner': 'La mesa está llena — fin del juego.',
  'table_full_title': '¡Mesa llena!',
  'table_full_body': '¿Ver un anuncio para quitar todo\nel vodka y el ron y seguir jugando?',
  'watch_ad_clear': 'Ver Anuncio y Despejar Chupitos',
  'end_game': 'Terminar Juego',
  'ad_playing': 'Reproduciendo anuncio…',
  'game_over': 'Fin del Juego',
  'cocktails_made_label': 'Cócteles hechos',
  'play_again': 'Jugar de Nuevo',
  'home': 'Inicio',
  'ads_consent_title': 'Los Anuncios Mantienen Mixoloco Gratis',
  'ads_consent_body':
      'Nos gustaría mostrar anuncios adaptados a ti, lo que ayuda a que paguen mejor. '
      'Verás anuncios de todos modos — esto solo decide si son personalizados. '
      'Puedes cambiar de opinión cuando quieras.',
  'allow': 'Permitir',
  'no_thanks': 'No, gracias',
  'advertisement': 'ANUNCIO',
  'continue_label': 'Continuar',
  'continue_in': 'Continuar en',
  'ad_not_ready': 'Anuncio no disponible — inténtalo de nuevo en un momento',
  'shop_watch_ad_title': 'Ve un anuncio por',
  'shop_watch_ad_button': 'Ver Anuncio',
  'shop_credits_earned': '¡Créditos ganados!',
  'level_complete_title': '¡Nivel Completado!',
  'onto_next_level': '¡Al siguiente nivel!',
  'reset_progress': 'Restablecer Progreso',
  'reset_progress_button': 'Restablecer',
  'reset_progress_confirm_title': '¿Restablecer tu progreso?',
  'reset_progress_confirm_body': 'Esto devuelve tu evolución y nivel al inicio. Tus créditos no se verán afectados.',
  'cancel': 'Cancelar',
};
