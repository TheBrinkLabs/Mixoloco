import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/progression_service.dart';

/// The app's supported languages — English (default) plus Spanish as the
/// first translated pilot. Adding a language means adding a case here
/// and a matching entry in every map in core/i18n/strings.dart.
enum AppLocale { en, es }

class LocaleNotifier extends Notifier<AppLocale> {
  @override
  AppLocale build() {
    _loadPersisted();
    return AppLocale.en;
  }

  Future<void> _loadPersisted() async {
    final code = await loadLocaleCode();
    state = code == 'es' ? AppLocale.es : AppLocale.en;
  }

  Future<void> setLocale(AppLocale locale) async {
    state = locale;
    await saveLocaleCode(locale == AppLocale.es ? 'es' : 'en');
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, AppLocale>(LocaleNotifier.new);
