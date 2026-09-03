import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';
import 'home_screen.dart';

/// A short branded intro (mark pops in, name reveals, brief hold) shown once
/// on cold start - the native launch screen is static, so this is where the
/// actual "wow" moment lives before handing off to HomeScreen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _totalDuration = Duration(milliseconds: 1900);

  late final AnimationController _controller;
  late final Animation<double> _markScale;
  late final Animation<double> _markOpacity;
  late final Animation<double> _wordOpacity;
  late final Animation<Offset> _wordSlide;

  bool _showHome = false;
  LatLng? _resolvedLatLng;
  LocationAccessResult? _resolvedAccessError;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _totalDuration);

    _markOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.05, 0.28, curve: Curves.easeOut),
    );
    _markScale = Tween(begin: 0.4, end: 1.0).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.05, 0.48, curve: Curves.easeOutBack),
    ));
    _wordOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.36, 0.60, curve: Curves.easeOut),
    );
    _wordSlide = Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.36, 0.62, curve: Curves.easeOutCubic),
      ),
    );

    _controller.forward();
    _prepare();
  }

  /// Resolves location in parallel with the animation - by the time both
  /// settle, HomeScreen can skip its own blank loading spinner. Capped so a
  /// stuck GPS fix can't hold the branded splash open indefinitely; past
  /// that, HomeScreen just resolves it live like before.
  Future<void> _prepare() async {
    await Future.wait([
      Future.delayed(_totalDuration),
      _resolveLocation().timeout(const Duration(seconds: 6),
          onTimeout: () {}),
    ]);
    if (mounted) setState(() => _showHome = true);
  }

  Future<void> _resolveLocation() async {
    final result = await LocationService.ensurePermissions(background: false);
    if (result == LocationAccessResult.serviceDisabled ||
        result == LocationAccessResult.denied ||
        result == LocationAccessResult.deniedForever) {
      _resolvedAccessError = result;
      return;
    }
    try {
      final pos = await LocationService.getCurrentPosition();
      _resolvedLatLng = LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      // Leave both null - HomeScreen falls back to resolving it itself.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      child: _showHome
          ? HomeScreen(
              key: const ValueKey('home'),
              initialLatLng: _resolvedLatLng,
              initialLocationAccessError: _resolvedAccessError,
            )
          : _buildSplash(key: const ValueKey('splash')),
    );
  }

  Widget _buildSplash({required Key key}) {
    return Container(
      key: key,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF62A8FF), Color(0xFF103794)],
        ),
      ),
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: _markOpacity.value,
                  child: Transform.scale(
                    scale: _markScale.value,
                    child: Image.asset(
                      'assets/icon/app_icon_foreground.png',
                      width: 140,
                      height: 140,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SlideTransition(
                  position: _wordSlide,
                  child: FadeTransition(
                    opacity: _wordOpacity,
                    child: const Text(
                      'ARRIVE ALERT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3.5,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
