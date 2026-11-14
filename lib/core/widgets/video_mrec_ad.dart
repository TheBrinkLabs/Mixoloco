import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'aluna_mrec_ad.dart';

const _capitlePlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.brinklabs.capitle';

/// A second fallback for the score-milestone MREC ad break (see
/// ad_break_screen.dart), alongside AlunaMrecAd — a real local video
/// creative (assets/videos/mrec_fallback_ad.mp4, a Capitle-branded MREC
/// creative sized for a 300x250 slot same as Aluna's card) rather than a
/// network ad. Muted and looping, and — like AlunaMrecAd — the whole
/// card is tappable and opens Capitle's real Play Store listing. Which
/// of the two shows on a given ad break is picked once per break (see
/// ad_break_screen.dart), not alternated on a timer the way Capitle's
/// own persistent house banner does, since this screen itself is only
/// ever on-screen briefly.
class VideoMrecAd extends StatefulWidget {
  const VideoMrecAd({super.key});

  @override
  State<VideoMrecAd> createState() => _VideoMrecAdState();
}

class _VideoMrecAdState extends State<VideoMrecAd> {
  /// Set once this device's decoder has failed on the video, so later ad
  /// breaks go straight to the Aluna card instead of retrying it.
  static bool _videoUnsupported = false;

  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (_videoUnsupported) return;
    final controller = VideoPlayerController.asset('assets/videos/mrec_fallback_ad.mp4');
    _controller = controller;
    controller.addListener(_onVideoUpdate);
    controller
      ..setVolume(0)
      ..setLooping(true)
      // Without this catchError a decoder failure was an unhandled async
      // error, which main.dart reports to Crashlytics as a fatal crash.
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        controller.play();
      }).catchError((Object e) {
        debugPrint('Video MREC failed: $e');
        _markUnsupported();
      });
  }

  // Decoder errors can also surface after initialize() succeeds.
  void _onVideoUpdate() {
    if (_controller?.value.hasError ?? false) _markUnsupported();
  }

  void _markUnsupported() {
    _videoUnsupported = true;
    if (mounted) setState(() => _ready = false);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoUpdate);
    _controller?.dispose();
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
    // This device can't play the video — show the Aluna card instead of
    // an empty black box.
    if (_videoUnsupported) return const AlunaMrecAd();
    final controller = _controller!;
    return GestureDetector(
      onTap: _openPlayStore,
      child: Container(
        width: 300,
        height: 250,
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: _ready
            ? FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(width: controller.value.size.width, height: controller.value.size.height, child: VideoPlayer(controller)),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
