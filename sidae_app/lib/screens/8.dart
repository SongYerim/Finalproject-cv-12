import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class BusOnlyScreen extends StatefulWidget {
  final double? returnMidLat;
  final double? returnMidLng;
  final double returnDistanceMeters;

  const BusOnlyScreen({
    super.key,
    this.returnMidLat,
    this.returnMidLng,
    this.returnDistanceMeters = 25.0,
  });

  @override
  State<BusOnlyScreen> createState() => _BusOnlyScreenState();
}

class _BusOnlyScreenState extends State<BusOnlyScreen> {
  String? _lastImagePath;
  String _lastResponse = 'No response';
  Timer? _previewTimer;
  StreamSubscription? _exitDistanceSubscription;

  static const MethodChannel _channel = MethodChannel(
    'com.ctrlcv.sidae_app/yolo_native',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.ctrlcv.sidae_app/yolo_detections',
  );

  String _getCaptureUploadUrl() {
    // .env에서 SIDAE_SERVER_CLOUD_URL 불러오기
    final baseUrl = dotenv.env['SIDAE_SERVER_CLOUD_URL'];
    if (baseUrl == null || baseUrl.isEmpty) {
      throw Exception('SIDAE_SERVER_CLOUD_URL이 .env 파일에 설정되지 않았습니다.');
    }
    // baseUrl/bus-ai/bus-recognition 엔드포인트
    return '$baseUrl/bus-ai/bus-recognition';
  }

  Future<void> _captureAndUpload(BuildContext context, String source) async {
    try {
      if (mounted) {
        setState(() {
          _lastResponse = 'No response';
        });
      }

      // source에 따라 mode 설정
      // 하차벨: 'stop_bell' -> mode: 'bell'
      // 교통카드 태그기: 'card_tagger' -> mode: 'tags_'
      final mode = source == 'stop_bell' ? 'bell' : 'tag_';

      final result = await _channel.invokeMethod('captureAndUploadImage', {
        'uploadUrl': _getCaptureUploadUrl(),
        'jpegQuality': 90,
        'metadata': {
          'source': source,
          'mode': mode, // source에 따라 mode 설정
        },
        'keepFile': true,
      });

      // 업로드 완료 후 즉시 카메라 종료
      await _channel.invokeMethod('stopCamera').catchError((_) {});

      if (result is Map) {
        final path = result['localPath'];
        final body = result['body'];
        if (mounted) {
          setState(() {
            if (path is String) {
              _lastImagePath = path;
            }
            final bodyText = body?.toString() ?? '';
            final normalized = bodyText.trim();
            _lastResponse =
                normalized.isNotEmpty && normalized.toLowerCase() != 'null'
                ? normalized
                : 'No response';
          });
        }
        _previewTimer?.cancel();
        _previewTimer = Timer(const Duration(seconds: 3), () {
          if (!mounted) return;
          setState(() {
            _lastImagePath = null;
          });
        });
      }

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('업로드 완료: $result')));
      }
    } catch (e) {
      await _channel.invokeMethod('stopCamera').catchError((_) {});
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('업로드 실패: $e')));
      }
      if (mounted) {
        setState(() {
          _lastResponse = 'No response';
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _startNativeReturnTrackingIfNeeded();
  }

  void _startNativeReturnTrackingIfNeeded() {
    final lat = widget.returnMidLat;
    final lng = widget.returnMidLng;
    if (lat == null || lng == null) return;

    _exitDistanceSubscription = _eventChannel.receiveBroadcastStream().listen((
      event,
    ) {
      if (event is Map && event['type'] == 'exitDistance') {
        final reached = event['reached'] as bool? ?? false;
        if (reached) {
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      }
    }, onError: (_) {});

    _channel
        .invokeMethod('startExitTracking', {'exitLat': lat, 'exitLng': lng})
        .catchError((_) {});
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _previewTimer = null;
    _exitDistanceSubscription?.cancel();
    _exitDistanceSubscription = null;
    _channel.invokeMethod('stopExitTracking').catchError((_) {});
    _channel.invokeMethod('stopCamera').catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 64),
              child: Column(
                children: [
                  Expanded(
                    child: _ActionPanel(
                      title: '하차벨',
                      backgroundColor: Colors.black,
                      accentColor: const Color(0xFFFFD400),
                      textColor: const Color(0xFFFFD400),
                      alignment: Alignment.center,
                      onTap: () => _captureAndUpload(context, 'stop_bell'),
                    ),
                  ),
                  Expanded(
                    child: _ActionPanel(
                      title: '교통카드\n태그기',
                      backgroundColor: const Color(0xFFFFD400),
                      accentColor: Colors.black,
                      textColor: Colors.black,
                      alignment: Alignment.center,
                      onTap: () => _captureAndUpload(context, 'card_tagger'),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD400),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  elevation: 2,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back, size: 20),
                    SizedBox(width: 6),
                    Text('뒤로가기', style: TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            if (_lastImagePath != null)
              Positioned(
                left: 16,
                right: 16,
                top: 12,
                child: Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFFFD400),
                      width: 2,
                    ),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(_lastImagePath!), fit: BoxFit.cover),
                        Positioned.fill(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              margin: const EdgeInsets.all(8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _lastResponse.isNotEmpty
                                    ? _lastResponse
                                    : 'No response',
                                textAlign: TextAlign.center,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
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

class _ActionPanel extends StatelessWidget {
  final String title;
  final Color backgroundColor;
  final Color accentColor;
  final Color textColor;
  final Alignment alignment;
  final VoidCallback? onTap;

  const _ActionPanel({
    required this.title,
    required this.backgroundColor,
    required this.accentColor,
    required this.textColor,
    required this.alignment,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox.expand(
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accentColor, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 26,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      Expanded(
                        child: Align(
                          alignment: alignment,
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
