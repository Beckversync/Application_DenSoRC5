import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

class Robot3DPanel extends StatefulWidget {
  const Robot3DPanel({
    super.key,
    required this.joints,
    this.modelAssetPath = 'assets/models/arctos.glb',
    this.height = 360,
  });

  final List<double> joints;
  final String modelAssetPath;
  final double height;

  @override
  State<Robot3DPanel> createState() => _Robot3DPanelState();
}

class _Robot3DPanelState extends State<Robot3DPanel> {
  late final WebViewController _controller;

  bool _viewerReady = false;
  bool _modelSent = false;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'RobotViewer',
        onMessageReceived: (message) async {
          debugPrint('RobotViewer: ${message.message}');

          if (message.message == 'ready') {
            _viewerReady = true;
            await _sendModelIfNeeded();
            await _pushJoints();
          }
        },
      )
      ..loadFlutterAsset('assets/web/robot_viewer.html');
  }

  @override
  void didUpdateWidget(covariant Robot3DPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameAngles(oldWidget.joints, widget.joints)) {
      _pushJoints();
    }
  }

  bool _sameAngles(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.001) {
        return false;
      }
    }
    return true;
  }

  Future<void> _sendModelIfNeeded() async {
    if (!_viewerReady || _modelSent) return;

    try {
      final ByteData data = await rootBundle.load(widget.modelAssetPath);
      final Uint8List bytes = data.buffer.asUint8List();
      final String base64Model = base64Encode(bytes);

      await _controller.runJavaScript(
        'window.setModelBase64(${jsonEncode(base64Model)});',
      );

      _modelSent = true;
      debugPrint('Robot model sent to viewer.');
    } catch (error) {
      debugPrint('Failed to send model: $error');
    }
  }

  Future<void> _pushJoints() async {
    if (!_viewerReady || !_modelSent || widget.joints.length < 6) return;

    final payload = jsonEncode(<String, dynamic>{
      'anglesDeg': widget.joints.take(6).toList(),
    });

    try {
      await _controller.runJavaScript('window.updateRobot($payload);');
    } catch (error) {
      debugPrint('runJavaScript error: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            Positioned(
              top: 12,
              right: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    '3D Robot View',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}