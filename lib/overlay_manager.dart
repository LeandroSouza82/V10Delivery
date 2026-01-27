import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class OverlayManager with WidgetsBindingObserver {
  static const MethodChannel _platform = MethodChannel('app.channel.launcher');

  static final OverlayManager _instance = OverlayManager._internal();
  factory OverlayManager() => _instance;
  OverlayManager._internal();

  void init() {
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _showOverlay();
    } else if (state == AppLifecycleState.resumed) {
      _closeOverlay();
    }
  }

  Future<void> _showOverlay() async {
    // Request permission if needed
    final hasPerm = await FlutterOverlayWindow.isPermissionGranted();
    if (!hasPerm) {
      await FlutterOverlayWindow.requestPermission();
      // Small delay to allow user to grant permission
      await Future.delayed(const Duration(milliseconds: 500));
      final granted = await FlutterOverlayWindow.isPermissionGranted();
      if (!granted) {
        // Open overlay settings so user can grant permission manually
        try {
          await _platform.invokeMethod('openOverlaySettings');
        } catch (_) {}
        return;
      }
    }

    // Show overlay: uses a Dart entrypoint named 'overlayMain'
    // Ensure foreground service is running so system keeps the app responsive
    try {
      await _platform.invokeMethod('startForegroundService');
    } catch (_) {}

    await FlutterOverlayWindow.showOverlay(
      height: -1,
      width: -1,
      alignment: OverlayAlignment.centerRight,
      enableDrag: false,
      // overlayContent is the name of the entrypoint function below
      overlayContent: 'overlayMain',
      overlayTitle: 'v10_overlay',
    );
  }

  Future<void> _closeOverlay() async {
    await FlutterOverlayWindow.closeOverlay();
  }

  // Helper invoked from overlay UI to bring the app to front
  static Future<void> bringAppToFront() async {
    try {
      await _platform.invokeMethod('bringToFront');
    } catch (e) {
      // ignore errors
    }
  }
}

// Entry point executed inside the overlay process. Must be top-level and have
// the vm entry-point pragma so it isn't tree-shaken.
@pragma('vm:entry-point')
void overlayMain() {
  runApp(const _OverlayApp());
}

class _OverlayApp extends StatelessWidget {
  const _OverlayApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: _OverlayIcon(),
          ),
        ),
      ),
    );
  }
}

class _OverlayIcon extends StatefulWidget {
  @override
  State<_OverlayIcon> createState() => _OverlayIconState();
}

class _OverlayIconState extends State<_OverlayIcon> {
  double posX = -1;
  double posY = -1;

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    try {
      final res = await MethodChannel('app.channel.launcher').invokeMethod('getOverlayPosition');
      if (res is Map) {
        final x = (res['x'] as double?) ?? -1.0;
        final y = (res['y'] as double?) ?? -1.0;
        // stored as normalized (0.0 - 1.0) values; keep normalized in state
        setState(() {
          posX = x;
          posY = y;
        });
      }
    } catch (_) {}
  }

  Future<void> _savePosition(double normX, double normY) async {
    try {
      await MethodChannel('app.channel.launcher').invokeMethod('saveOverlayPosition', {'x': normX, 'y': normY});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Default to bottom-right if no saved normalized position
    double startX = (posX >= 0)
        ? (posX * size.width)
        : (size.width - 70);
    double startY = (posY >= 0)
        ? (posY * size.height)
        : (size.height - 70);

    double currentX = startX;
    double currentY = startY;

    return Stack(
      children: [
        Positioned(
          left: currentX,
          top: currentY,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                currentX += details.delta.dx;
                currentY += details.delta.dy;
              });
            },
            onPanEnd: (details) async {
              // Save normalized position (percent) so it adapts to screen sizes
              final normX = (currentX / size.width).clamp(0.0, 1.0);
              final normY = (currentY / size.height).clamp(0.0, 1.0);
              await _savePosition(normX, normY);
            },
            onTap: () async {
              await FlutterOverlayWindow.closeOverlay();
              await OverlayManager.bringAppToFront();
            },
            child: Opacity(
              opacity: 0.6,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  image: const DecorationImage(
                    image: AssetImage('assets/images/icone_sf.png'),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
