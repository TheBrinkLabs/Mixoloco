import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

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
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset('assets/videos/mrec_fallback_ad.mp4');
    _controller
      ..setVolume(0)
      ..setLooping(true)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
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
                child: SizedBox(width: _controller.value.size.width, height: _controller.value.size.height, child: VideoPlayer(_controller)),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
