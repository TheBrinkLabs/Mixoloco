import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/widgets/submenu_kit.dart';

/// The Guide's "How to Play" rules page — numbered steps grouped under
/// section headings (basics, levelling up in each Cocktail Mode, power-ups),
/// numbering running continuously across sections.
class HowToPlayScreen extends ConsumerWidget {
  const HowToPlayScreen({super.key});

  static const _sections = [
    ('how_to_play_basics', [1, 2, 3, 4]),
    ('how_to_play_levels', [5, 6, 7, 8]),
    ('how_to_play_powerups', [9, 10]),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);

    return SubmenuScaffold(
      title: tr(locale, 'how_to_play'),
      panelBottom: 64,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var s = 0; s < _sections.length; s++) ...[
              Padding(
                padding: EdgeInsets.only(top: s == 0 ? 0 : 22, bottom: 12),
                child: Text(
                  tr(locale, _sections[s].$1),
                  style: const TextStyle(
                    fontFamily: 'Lilita One',
                    fontSize: 20,
                    color: SubmenuColors.goldTop,
                  ),
                ),
              ),
              for (final n in _sections[s].$2)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _Step(number: n, text: tr(locale, 'how_to_play_step_$n')),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: SubmenuColors.goldEdge, width: 2),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [SubmenuColors.goldTop, SubmenuColors.goldBottom],
            ),
          ),
          child: Text(
            '$number',
            style: const TextStyle(fontFamily: 'Lilita One', fontSize: 15, color: Colors.white),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: submenuNunito(size: 14, weight: FontWeight.w800, color: Colors.white, height: 1.35),
          ),
        ),
      ],
    );
  }
}
