import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../i18n/strings.dart';
import '../services/locale_provider.dart';
import '../theme/app_theme.dart';

const _capitlePlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.brinklabs.capitle';

/// Stands in for the real rewarded "clear shots and continue" ad (see
/// GameScreen._watchAdToContinue) when it isn't available — not
/// configured yet, or no fill. Rather than leaving the continue-offer
/// as a dead end, this plays a short YouTube video in its place, with
/// the same "minimum watch, then continue" shape as the MREC ad break
/// (see ad_break_screen.dart). Returns true once the player's watched
/// long enough to continue, false if they back out early — the caller
/// treats a false the same as declining the offer outright.
Future<bool> showContinueFallbackVideo(BuildContext context, AppLocale locale) async {
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => _ContinueFallbackVideoScreen(locale: locale)),
  );
  return result ?? false;
}

class _ContinueFallbackVideoScreen extends StatefulWidget {
  final AppLocale locale;
  const _ContinueFallbackVideoScreen({required this.locale});

  @override
  State<_ContinueFallbackVideoScreen> createState() => _ContinueFallbackVideoScreenState();
}

class _ContinueFallbackVideoScreenState extends State<_ContinueFallbackVideoScreen> {
  // https://www.youtube.com/shorts/UKKli--cBoM
  static const _videoId = 'UKKli--cBoM';
  static const _minWatchSeconds = 8;

  late final WebViewController _controller;
  bool _canContinue = false;
  int _secondsRemaining = _minWatchSeconds;
  Timer? _countdownTimer;

  static const _embedHtml = '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden;}
iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0;}</style>
</head>
<body>
<iframe src="https://www.youtube.com/embed/$_videoId?autoplay=1&playsinline=1&rel=0&controls=1"
  allow="autoplay; encrypted-media" allowfullscreen></iframe>
</body>
</html>
''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black);
    // Android WebView blocks autoplaying media without a user gesture by
    // default — the embed URL's autoplay=1 param can't override that on
    // its own, so this needs to be turned off explicitly.
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    // Loading the bare /embed/ URL directly (loadRequest) gives
    // YouTube's player no real page origin to validate the request
    // against, which is what was showing as "video configuration
    // error" — wrapping it in a minimal HTML page with an explicit
    // baseUrl gives it one, which is the standard fix for embedding
    // YouTube reliably inside a WebView.
    _controller.loadHtmlString(_embedHtml, baseUrl: 'https://www.youtube.com');
    // The countdown runs on our own timer rather than anything the
    // embedded player reports — same reasoning as the MREC ad break:
    // there's no reliable "did they actually watch" signal to hook into
    // for an arbitrary embedded page, so this is a product-level stand-in
    // for that, not a real playback-completion check.
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() {
          _secondsRemaining = 0;
          _canContinue = true;
        });
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _openPlayStore() async {
    final uri = Uri.parse(_capitlePlayStoreUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  tr(widget.locale, 'advertisement'),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.textMuted),
                ),
              ),
              GestureDetector(
                onTap: _openPlayStore,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFF00D2FF), Color(0xFF00F076), Color(0xFFFFCF00), Color(0xFFFF3A44)],
                          stops: [0.0, 0.4, 0.65, 1.0],
                        ).createShader(bounds),
                        child: const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Capitle — get it on Google Play',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: WebViewWidget(controller: _controller)),
              Padding(
                padding: const EdgeInsets.all(20),
                child: GestureDetector(
                  onTap: _canContinue ? () => Navigator.of(context).pop(true) : null,
                  child: AnimatedOpacity(
                    opacity: _canContinue ? 1.0 : 0.5,
                    duration: const Duration(milliseconds: 250),
                    child: Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: _canContinue ? AppColors.gradientSunset : null,
                        color: _canContinue ? null : AppColors.surface2,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: _canContinue
                            ? [BoxShadow(color: AppColors.sunsetOrange.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 5))]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          _canContinue ? tr(widget.locale, 'continue_label') : '${tr(widget.locale, 'continue_in')} ${_secondsRemaining}s',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _canContinue ? Colors.black : AppColors.textMuted),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
