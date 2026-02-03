import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/signal_state_service.dart';
import '../services/tts_service.dart';
import '../services/crosswalk_direction_service.dart';

/// YOLO 온디바이스 객체 감지 테스트 화면
///
/// 구현 내용:
/// - 네이티브 CameraX + Kotlin 기반 카메라 스트림
/// - 네이티브 전처리 (YUV → RGB → Float32)
/// - 네이티브 TFLite 추론 (GPU Delegate → NNAPI → CPU)
/// - 네이티브 NMS 후처리
/// - 네이티브 바운딩 박스 오버레이 렌더링 (카메라 프리뷰 위에 표시)
/// - FPS 측정
/// - 횡단보도 반대편 도달 시 자동 종료
class YoloTestScreen extends StatefulWidget {
  /// 횡단보도 반대편 좌표 (nullable - 없으면 자동 종료 비활성화)
  final double? exitLat;
  final double? exitLng;

  const YoloTestScreen({super.key, this.exitLat, this.exitLng});

  @override
  State<YoloTestScreen> createState() => _YoloTestScreenState();
}

class _YoloTestScreenState extends State<YoloTestScreen> {
  // 네이티브 카메라 채널
  static const MethodChannel _cameraChannel = MethodChannel(
    'com.ctrlcv.sidae_app/yolo_native',
  );
  static const EventChannel _detectionsChannel = EventChannel(
    'com.ctrlcv.sidae_app/yolo_detections',
  );
  StreamSubscription? _detectionsSubscription;

  bool _isCameraInitialized = false;
  bool _permissionDenied = false;

  // YOLO 결과
  List<Detection> _detections = [];

  // FPS (네이티브에서 받음)
  double _fps = 0.0;

  // 신호 상태 서비스
  final SignalStateService _signalStateService = SignalStateService.instance;
  SignalState _currentSignalState = SignalState.init;
  SignalConsensus _currentConsensus = SignalConsensus.unknown;

  // GPS 추적 및 자동 종료 (네이티브에서 처리)
  bool _hasReachedExit = false;
  Timer? _exitTimer;
  int _exitCountdown = 10; // 10초 카운트다운

  // 공간음향 방향 안내 서비스
  final CrosswalkDirectionService _directionService =
      CrosswalkDirectionService();
  double _deviceHeading = 0.0;
  double _exitBearing = 0.0;
  double _angleDiff = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _requestCameraPermission();
  }

  /// 서비스 초기화
  Future<void> _initializeServices() async {
    // SignalStateService 상태 초기화 (이전 세션의 상태 제거)
    _signalStateService.reset();

    // TTS 서비스 초기화
    await TtsService.instance.initialize();

    // 신호 상태 변경 콜백 설정
    _signalStateService.onStateChanged = (state, consensus) {
      if (!mounted) return;
      setState(() {
        _currentSignalState = state;
        _currentConsensus = consensus;
      });
      
      // 신호등 상태에 따라 공간음향 제어
      _controlSpatialAudioBySignal(state, consensus);
    };

    // 반대편 좌표가 있으면 GPS 추적 및 공간음향 시작
    if (widget.exitLat != null && widget.exitLng != null) {
      _startExitTracking();
      _startDirectionGuidance();
    }
  }

  /// 공간음향 방향 안내 시작
  Future<void> _startDirectionGuidance() async {
    // 방향 업데이트 콜백 설정
    _directionService.onDirectionUpdate =
        (deviceHeading, exitBearing, angleDiff) {
          if (!mounted) return;
          setState(() {
            _deviceHeading = deviceHeading;
            _exitBearing = exitBearing;
            _angleDiff = angleDiff;
          });
        };

    // 서비스 시작 (공간음향은 신호등 상태에 따라 별도로 제어)
    final success = await _directionService.start(
      exitLat: widget.exitLat!,
      exitLng: widget.exitLng!,
    );

    if (success) {
      // TTS로 안내
      await TtsService.instance.speak('소리가 나는 방향이 횡단보도 끝지점입니다.');
    }
  }

  /// 신호등 상태에 따라 공간음향 제어
  Future<void> _controlSpatialAudioBySignal(
    SignalState state,
    SignalConsensus consensus,
  ) async {
    // 초록불이고 건너가는 상태(crossing)일 때만 공간음향 재생
    if (state == SignalState.crossing && consensus == SignalConsensus.green) {
      await _directionService.startSpatialAudio();
    } else {
      // 빨간불이거나 대기 상태일 때는 공간음향 중지
      await _directionService.stopSpatialAudio();
    }
  }

  /// 횡단보도 반대편 도달 추적 시작 (네이티브 GPS 사용)
  Future<void> _startExitTracking() async {
    try {
      await _cameraChannel.invokeMethod('startExitTracking', {
        'exitLat': widget.exitLat,
        'exitLng': widget.exitLng,
      });
    } catch (e) {
      // 무시
    }
  }

  /// 횡단보도 반대편 도달 시 호출
  void _onReachedExit() {
    if (_hasReachedExit) return;
    _hasReachedExit = true;

    TtsService.instance.speak('횡단보도를 거의 다 건넜습니다. 10초 후 카메라가 종료됩니다.');

    // 10초 카운트다운 타이머 시작
    _exitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _exitCountdown--;
      });

      if (_exitCountdown <= 0) {
        timer.cancel();
        _closeScreen();
      }
    });
  }

  /// 화면 종료
  void _closeScreen() {
    if (!mounted) return;
    Navigator.pop(context);
  }

  /// 카메라 권한 요청
  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.status;
    if (!status.isGranted) {
      final result = await Permission.camera.request();
      if (!result.isGranted) {
        // 권한 거부 처리
        if (!mounted) return;
        setState(() {
          _permissionDenied = true;
        });
        return;
      }
    }

    // 권한이 허용된 경우
    if (!mounted) return;
    setState(() {
      _permissionDenied = false;
    });

    // 네이티브 카메라 초기화
    await _initializeNativeCamera();
  }

  /// 네이티브 카메라 초기화 (CameraX + Kotlin)
  Future<void> _initializeNativeCamera() async {
    try {
      // 모델과 라벨 로드
      const modelPath = 'assets/best_float16.tflite';
      final modelBytes = await rootBundle.load(modelPath);
      final labelsData = await rootBundle.loadString(
        'assets/custom_labels.txt',
      );

      // 1. YOLO 모델 초기화
      final initResult = await _cameraChannel.invokeMethod('initialize', {
        'modelBytes': modelBytes.buffer.asUint8List(),
        'labelsText': labelsData,
        'modelPath': modelPath, // 모델 파일명 전달
      });

      if (initResult is! Map || initResult['initialized'] != true) {
        return;
      }

      // 2. 결과 스트림 리스닝 (카메라 시작 전에 설정)
      _detectionsSubscription = _detectionsChannel
          .receiveBroadcastStream()
          .listen(
            (dynamic result) {
              if (result is Map) {
                // FPS 업데이트 (네이티브에서 받음)
                if (result['fps'] != null) {
                  final nativeFps = (result['fps'] as num).toDouble();
                  if (!mounted) return;
                  setState(() {
                    _fps = nativeFps;
                  });
                }

                // 감지 결과 업데이트
                if (result['detections'] != null) {
                  final detectionsList = (result['detections'] as List).map((
                    d,
                  ) {
                    final map = d as Map;
                    return Detection(
                      label: map['label'] as String,
                      confidence: (map['confidence'] as num).toDouble(),
                      bbox: (map['bbox'] as List)
                          .map((e) => (e as num).toDouble())
                          .toList(),
                    );
                  }).toList();

                  if (!mounted) return;
                  setState(() {
                    _detections = detectionsList;
                  });

                  // 신호 상태 서비스에 감지 결과 전달
                  final signalDetections = detectionsList
                      .map<Map<String, dynamic>>(
                        (d) => {'label': d.label, 'confidence': d.confidence},
                      )
                      .toList();

                  _signalStateService.processDetections(signalDetections);
                }

                // 네이티브 GPS 추적 결과 처리
                if (result['type'] == 'exitDistance') {
                  final reached = result['reached'] as bool;

                  if (reached && !_hasReachedExit) {
                    _onReachedExit();
                  }
                }

                // Heading 이벤트 처리 (CrosswalkDirectionService로 전달)
                if (result['type'] == 'heading') {
                  final heading = (result['heading'] as num).toDouble();
                  _directionService.handleHeadingEvent(heading);
                }
              }
            },
            onError: (error) {
              // 무시
            },
          );

      // 3. 카메라 시작
      await _cameraChannel.invokeMethod('startCamera');

      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      // 무시
    }
  }

  @override
  void dispose() {
    // 네이티브 카메라 먼저 중지 (비동기지만 fire-and-forget)
    _cameraChannel.invokeMethod('stopCamera').catchError((e) {
      // 무시
    });
    // 신호 상태 서비스 콜백 해제
    _signalStateService.onStateChanged = null;
    // 네이티브 GPS 추적 중지
    _cameraChannel.invokeMethod('stopExitTracking').catchError((e) {
      // 무시
    });
    // 공간음향 방향 안내 중지
    _directionService.dispose();
    // 종료 타이머 취소
    _exitTimer?.cancel();
    // 감지 스트림 중지
    _detectionsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 권한 거부 시 UI
    if (_permissionDenied) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("카메라 권한 필요"),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                size: 100,
                color: Colors.grey,
              ),
              const SizedBox(height: 20),
              const Text(
                "YOLO 객체 감지를 위해\n카메라 권한이 필요합니다.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.white70),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: () => openAppSettings(),
                icon: const Icon(Icons.settings),
                label: const Text("설정으로 이동"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.black,
      );
    }

    // 카메라 초기화 대기
    if (!_isCameraInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("YOLO 객체 감지 (온디바이스)"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // 1. 카메라 프리뷰 영역 (배경) - 맨 뒤 레이어 (첫 번째 child)
          // Flutter Stack은 첫 번째 child를 가장 아래에 그립니다.
          Positioned.fill(
            child: AndroidView(
              viewType: 'cameraPreview',
              onPlatformViewCreated: (int viewId) {
                // PlatformView 생성됨
              },
            ),
          ),

          // 2. FPS 오버레이 (우측 상단) - 앞으로 나옴
          Positioned(
            top: 8.0,
            right: 16.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "FPS: ${_fps.toStringAsFixed(1)}",
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // 2.5. 신호 상태 오버레이 (좌측 상단)
          Positioned(
            top: 8.0,
            left: 16.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _getSignalStateColor().withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getSignalStateText(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "판정: ${_getConsensusText()}",
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    "버퍼: ${_signalStateService.bufferStatus}",
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),

          // 2.6. 공간음향 방향 안내 오버레이 (우측 상단 아래)
          if (widget.exitLat != null && widget.exitLng != null)
            Positioned(
              top: 50.0,
              right: 16.0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '🔊 방향 안내',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_getDirectionText()}',
                      style: const TextStyle(
                        color: Colors.yellowAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '각도차: ${_angleDiff.toStringAsFixed(0)}°',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 2.7. 종료 카운트다운 오버레이 (화면 중앙)
          if (_hasReachedExit)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.6),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.greenAccent,
                        size: 80,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '횡단보도를 거의 다 건넜습니다!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$_exitCountdown초 후 종료',
                        style: const TextStyle(
                          color: Colors.yellowAccent,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 3. 하단 감지 결과 패널 - 맨 앞으로 나옴
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 150,
              color: Colors.black.withValues(alpha: 0.8),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "감지된 객체: ${_detections.length}개",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _detections.length,
                      itemBuilder: (context, index) {
                        final det = _detections[index];
                        return Container(
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                det.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                "${(det.confidence * 100).toStringAsFixed(1)}%",
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 신호 상태에 따른 색상 반환
  Color _getSignalStateColor() {
    switch (_currentConsensus) {
      case SignalConsensus.red:
        return Colors.red;
      case SignalConsensus.green:
        return Colors.green;
      case SignalConsensus.unknown:
        return Colors.grey;
    }
  }

  /// 신호 상태 텍스트 반환
  String _getSignalStateText() {
    switch (_currentSignalState) {
      case SignalState.init:
        return "대기 중";
      case SignalState.waitForGreen:
        return "초록불 대기";
      case SignalState.crossing:
        return "횡단 중";
    }
  }

  /// 판정 결과 텍스트 반환
  String _getConsensusText() {
    switch (_currentConsensus) {
      case SignalConsensus.red:
        return "빨간불";
      case SignalConsensus.green:
        return "초록불";
      case SignalConsensus.unknown:
        return "판정 중";
    }
  }

  /// 방향 텍스트 반환
  String _getDirectionText() {
    if (_angleDiff.abs() < 15) {
      return '정면';
    } else if (_angleDiff < -15) {
      return '왼쪽 ${_angleDiff.abs().toStringAsFixed(0)}°';
    } else {
      return '오른쪽 ${_angleDiff.toStringAsFixed(0)}°';
    }
  }
}

/// Detection 클래스
class Detection {
  final String label;
  final double confidence;
  final List<double> bbox; // [x1, y1, x2, y2] (0~1 정규화)

  Detection({
    required this.label,
    required this.confidence,
    required this.bbox,
  });
}

// 바운딩 박스는 네이티브에서 그려지므로 Flutter CustomPainter 제거됨
