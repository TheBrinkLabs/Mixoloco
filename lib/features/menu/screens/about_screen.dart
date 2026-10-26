import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/widgets/game_logo.dart';
import '../../../core/widgets/submenu_kit.dart';

class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  // Null while loading — the version line just shows a blank value
  // briefly rather than a hardcoded number that could drift from
  // pubspec.yaml's own (see PackageInfo.fromPlatform, which reads the
  // actual installed build's version, not a string maintained by hand).
  String? _version;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);

    return SubmenuScaffold(
      title: tr(locale, 'about'),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GameLogo(height: 80),
            const SizedBox(height: 10),
            Text(
              '${tr(locale, 'version')} ${_version ?? ''}',
              style: const TextStyle(fontFamily: 'Lilita One', fontSize: 16, color: SubmenuColors.gold),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: SubmenuColors.inset),
              child: Text(
                tr(locale, 'about_credits_body'),
                textAlign: TextAlign.center,
                style: submenuNunito(size: 14, weight: FontWeight.w700, color: Colors.white, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
