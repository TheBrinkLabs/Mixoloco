import 'package:share_plus/share_plus.dart';

/// Composes and fires the native share sheet with a line of text plus the
/// Play Store link — the three call sites (game-complete, cocktail detail,
/// songs) each build their own locally-styled button and just call
/// [shareText], since they come from different button families
/// (StoneButton vs SubmenuGoldButton) and there's no single chrome worth
/// forcing on all three.
const _playStoreUrl = 'https://play.google.com/store/apps/details?id=com.brinklabs.mixoloco';

void shareText(String leadIn) {
  SharePlus.instance.share(ShareParams(text: '$leadIn $_playStoreUrl'));
}
