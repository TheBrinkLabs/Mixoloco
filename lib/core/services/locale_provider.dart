import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/progression_service.dart';

/// The app's supported languages — English (default), plus Spanish,
/// German, Italian, Japanese, and Korean. Adding a language means adding
/// a case here, a code in [_codeFor]/[_localeForCode], and a matching
/// entry in every map in core/i18n/strings.dart.
enum AppLocale { en, es, de, it, ja, ko }

String _codeFor(AppLocale locale) => switch (locale) {
  AppLocale.en => 'en',
  AppLocale.es => 'es',
  AppLocale.de => 'de',
  AppLocale.it => 'it',
  AppLocale.ja => 'ja',
  AppLocale.ko => 'ko',
};

AppLocale _localeForCode(String code) => switch (code) {
  'es' => AppLocale.es,
  'de' => AppLocale.de,
  'it' => AppLocale.it,
  'ja' => AppLocale.ja,
  'ko' => AppLocale.ko,
  _ => AppLocale.en,
};

class LocaleNotifier extends Notifier<AppLocale> {
  @override
  AppLocale build() {
    _loadPersisted();
    return AppLocale.en;
  }

  Future<void> _loadPersisted() async {
    final code = await loadLocaleCode();
    state = _localeForCode(code);
  }

  Future<void> setLocale(AppLocale locale) async {
    state = locale;
    await saveLocaleCode(_codeFor(locale));
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, AppLocale>(LocaleNotifier.new);
