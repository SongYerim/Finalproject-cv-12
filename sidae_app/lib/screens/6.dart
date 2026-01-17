import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

/// YOLO26n 온디바이스 객체 감지 테스트 화면
/// 
/// 구현 내용:
/// - 실시간 카메라 스트림 (startImageStream)
/// - TFLite Interpreter 로드 (YOLO26n - 2026 최신)
/// - YUV → RGB 전처리
/// - Isolate 기반 추론
/// - NMS (Non-Maximum Suppression) 후처리
/// - CustomPainter 바운딩 박스 렌더링
/// - FPS 측정
class YoloTestScreen extends StatefulWidget {
  const YoloTestScreen({super.key});

  @override
  State<YoloTestScreen> createState() => _YoloTestScreenState();
}

class _YoloTestScreenState extends State<YoloTestScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isDetecting = false;
  bool _permissionDenied = false;
  
  // YOLO 결과
  List<Detection> _detections = [];
  
  // FPS 측정
  int _frameCount = 0;
  double _fps = 0.0;
  DateTime _lastFpsUpdate = DateTime.now();
  
  // Isolate 통신
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
    _initializeIsolate();
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
        debugPrint("❌ 카메라 권한이 거부되었습니다.");
        return;
      }
    }
    
    // 권한이 허용된 경우
    debugPrint("✅ 카메라 권한이 허용되었습니다.");
    if (!mounted) return;
    setState(() {
      _permissionDenied = false;
    });
    
    // 카메라 초기화
    await _initializeCamera();
  }

  /// 카메라 초기화
  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        debugPrint("❌ 카메라를 찾을 수 없습니다.");
        return;
      }

      _cameraController = CameraController(
        _cameras![0], // 후면 카메라
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420, // YUV 포맷
      );

      await _cameraController!.initialize();
      
      if (!mounted) return;
      
      setState(() {
        _isCameraInitialized = true;
      });

      // 카메라 스트림 시작
      _startImageStream();
      
      debugPrint("✅ 카메라 초기화 완료");
    } catch (e) {
      debugPrint("❌ 카메라 초기화 실패: $e");
    }
  }

  /// Isolate 초기화 (백그라운드 추론)
  Future<void> _initializeIsolate() async {
    try {
      // 메인 isolate에서 asset 미리 로드
      final labels = await rootBundle.loadString('assets/coco_labels.txt');
      final modelData = await rootBundle.load('assets/yolo26n_float16.tflite');
      
      _receivePort = ReceivePort();
      
      _isolate = await Isolate.spawn(
        _isolateEntry,
        {
          'sendPort': _receivePort!.sendPort,
          'labels': labels,
          'modelBytes': modelData.buffer.asUint8List(),
        },
      );

      _receivePort!.listen((message) {
        if (message is SendPort) {
          _sendPort = message;
          debugPrint("✅ Isolate SendPort 연결 완료");
        } else if (message is Map && message['error'] != null) {
          // 에러 수신
          debugPrint("❌ Isolate 에러: ${message['error']}");
          _isDetecting = false;
        } else if (message is List<Detection>) {
          // 추론 결과 수신
          if (!mounted) return;
          _frameCount++; // 처리 완료된 프레임만 카운트
          _isDetecting = false; // 처리 완료 후 플래그 해제
          
          // UI 업데이트 (바운딩 박스 표시)
          setState(() {
            _detections = message;
          });
          _updateFps(); // FPS 업데이트
          
          // 디버그: 탐지 결과 출력
          if (message.isNotEmpty) {
            debugPrint("🔍 감지: ${message.map((d) => '${d.label}(${(d.confidence * 100).toStringAsFixed(0)}%)').join(', ')}");
          }
        }
      });
    } catch (e) {
      debugPrint("❌ Isolate 초기화 실패: $e");
    }
  }

  /// Isolate 엔트리 포인트 (백그라운드 스레드)
  static void _isolateEntry(Map<String, dynamic> params) async {
    final mainSendPort = params['sendPort'] as SendPort;
    final labelData = params['labels'] as String;
    final modelBytes = params['modelBytes'] as Uint8List;
    
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    Interpreter? interpreter;
    List<String> labels;

    // 라벨 파싱 (메인에서 전달받음)
    labels = labelData.split('\n').where((line) => line.trim().isNotEmpty).toList();
    debugPrint("✅ [Isolate] 라벨 로드 완료: ${labels.length}개");

    // TFLite 모델 로드 (바이트 버퍼로 로드)
    try {
      interpreter = Interpreter.fromBuffer(modelBytes);
      debugPrint("✅ [Isolate] YOLO26n FP16 모델 로드 완료 (${modelBytes.length} bytes)");
    } catch (e) {
      debugPrint("❌ [Isolate] 모델 로드 실패: $e");
      mainSendPort.send({'error': 'Model load failed: $e'});
      return;
    }

    // 메인 스레드로부터 이미지 수신 대기
    await for (var message in receivePort) {
      if (message is Map<String, dynamic>) {
        final cameraImage = message['image'] as CameraImage;
        
        try {
          // 1. 전처리: YUV → RGB → 640x640
          final inputTensor = _preprocessImage(cameraImage);
          
          // 2. 추론 (모델 출력: [1, 300, 6] - NMS 적용된 형식)
          final outputTensor = List.filled(1 * 300 * 6, 0.0).reshape([1, 300, 6]);
          interpreter.run(inputTensor, outputTensor);
          
          // 3. 후처리: NMS가 이미 적용된 출력에서 Detection 추출
          final detections = _postprocessNMSOutput(outputTensor, labels);
          
          // 4. 결과 전송
          mainSendPort.send(detections);
        } catch (e, stackTrace) {
          // 에러를 메인으로 전송
          debugPrint("⚠️ [Isolate] 추론 에러: $e");
          debugPrint("⚠️ [Isolate] StackTrace: $stackTrace");
          mainSendPort.send({'error': e.toString()});
        }
      }
    }
  }

  /// 전처리: YUV420 → RGB → 640x640 정규화 (Letterbox 적용)
  static List<List<List<List<double>>>> _preprocessImage(CameraImage cameraImage) {
    // YUV420 → RGB 변환
    final rgbImage = _convertYUV420ToRGB(cameraImage);
    
    // 카메라 이미지 90도 회전 (Android 후면 카메라는 90도 회전되어 있음)
    final rotated = img.copyRotate(rgbImage, angle: 90);
    
    // Letterbox: 비율 유지하면서 640x640에 맞춤 (검은색 패딩)
    final resized = _letterboxResize(rotated, 640, 640);
    
    // [1, 640, 640, 3] 텐서로 변환 및 정규화 (0~1)
    final input = List.generate(
      1,
      (_) => List.generate(
        640,
        (y) => List.generate(
          640,
          (x) {
            final pixel = resized.getPixel(x, y);
            return [
              pixel.r / 255.0,
              pixel.g / 255.0,
              pixel.b / 255.0,
            ];
          },
        ),
      ),
    );
    
    return input;
  }
  
  /// Letterbox 리사이즈: 비율 유지하면서 타겟 크기에 맞춤
  static img.Image _letterboxResize(img.Image src, int targetWidth, int targetHeight) {
    final srcWidth = src.width;
    final srcHeight = src.height;
    
    // 스케일 계산 (비율 유지)
    final scale = (targetWidth / srcWidth) < (targetHeight / srcHeight)
        ? targetWidth / srcWidth
        : targetHeight / srcHeight;
    
    final newWidth = (srcWidth * scale).round();
    final newHeight = (srcHeight * scale).round();
    
    // 리사이즈
    final resized = img.copyResize(src, width: newWidth, height: newHeight);
    
    // 패딩 계산
    final padX = (targetWidth - newWidth) ~/ 2;
    final padY = (targetHeight - newHeight) ~/ 2;
    
    // 검은색 배경 이미지 생성
    final result = img.Image(width: targetWidth, height: targetHeight);
    img.fill(result, color: img.ColorRgb8(0, 0, 0));
    
    // 리사이즈된 이미지를 중앙에 배치
    img.compositeImage(result, resized, dstX: padX, dstY: padY);
    
    return result;
  }

  /// YUV420 → RGB 변환
  static img.Image _convertYUV420ToRGB(CameraImage cameraImage) {
    final width = cameraImage.width;
    final height = cameraImage.height;
    
    final yPlane = cameraImage.planes[0];
    final uPlane = cameraImage.planes[1];
    final vPlane = cameraImage.planes[2];
    
    final rgbImage = img.Image(width: width, height: height);
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final yIndex = y * yPlane.bytesPerRow + x;
        final uvIndex = (y ~/ 2) * uPlane.bytesPerRow + (x ~/ 2);
        
        final yValue = yPlane.bytes[yIndex];
        final uValue = uPlane.bytes[uvIndex];
        final vValue = vPlane.bytes[uvIndex];
        
        // YUV → RGB 변환 공식
        int r = (yValue + 1.402 * (vValue - 128)).round().clamp(0, 255);
        int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).round().clamp(0, 255);
        int b = (yValue + 1.772 * (uValue - 128)).round().clamp(0, 255);
        
        rgbImage.setPixelRgba(x, y, r, g, b, 255);
      }
    }
    
    return rgbImage;
  }

  /// 후처리: NMS가 이미 적용된 출력에서 Detection 추출
  /// 모델 출력: [1, 300, 6]
  /// - 300 = 최대 감지 수
  /// - 6 = (x1, y1, x2, y2, confidence, class_id) - 이미 0~1 정규화됨
  static List<Detection> _postprocessNMSOutput(List<dynamic> output, List<String> labels) {
    final detections = <Detection>[];
    const confidenceThreshold = 0.25;
    
    final data = output[0] as List; // [300, 6]
    
    for (int i = 0; i < 300; i++) {
      final detection = data[i] as List;
      
      // 좌표가 이미 0~1 정규화되어 있음 (640으로 나눌 필요 없음!)
      final x1 = (detection[0] as num).toDouble();
      final y1 = (detection[1] as num).toDouble();
      final x2 = (detection[2] as num).toDouble();
      final y2 = (detection[3] as num).toDouble();
      final confidence = (detection[4] as num).toDouble();
      final classId = (detection[5] as num).toInt();
      
      // confidence가 threshold 미만이면 건너뛰기
      if (confidence < confidenceThreshold) continue;
      
      // 유효하지 않은 bbox 건너뛰기
      if (x2 <= x1 || y2 <= y1) continue;
      
      // 클래스 ID가 범위를 벗어나면 건너뛰기
      if (classId < 0 || classId >= labels.length) continue;
      
      detections.add(Detection(
        label: labels[classId],
        confidence: confidence,
        bbox: [
          x1.clamp(0.0, 1.0),
          y1.clamp(0.0, 1.0),
          x2.clamp(0.0, 1.0),
          y2.clamp(0.0, 1.0),
        ],
      ));
    }
    
    return detections;
  }

  /// 카메라 스트림 시작
  void _startImageStream() {
    if (!_isCameraInitialized || _cameraController == null) {
      debugPrint("❌ 카메라가 초기화되지 않음");
      return;
    }
    
    _cameraController!.startImageStream((CameraImage image) {
      if (_isDetecting || _sendPort == null) {
        // 디버그: 건너뛴 프레임 카운트
        return;
      }
      
      _isDetecting = true;
      
      // Isolate로 이미지 전송
      _sendPort!.send({'image': image});
      
      // 플래그는 Isolate 결과 수신 시 해제됨
    });
    
    debugPrint("✅ 카메라 스트림 시작");
  }

  /// FPS 업데이트
  void _updateFps() {
    final now = DateTime.now();
    final diff = now.difference(_lastFpsUpdate).inMilliseconds;
    
    if (diff >= 1000) {
      setState(() {
        _fps = _frameCount / (diff / 1000.0);
      });
      _frameCount = 0;
      _lastFpsUpdate = now;
      debugPrint("📊 FPS: ${_fps.toStringAsFixed(1)}");
    }
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
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
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: () => openAppSettings(),
                icon: const Icon(Icons.settings),
                label: const Text("설정으로 이동"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.black,
      );
    }
    
    if (!_isCameraInitialized || _cameraController == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("YOLO26n 객체 감지 (온디바이스)"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          // FPS 표시
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
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
        ],
      ),
      body: Stack(
        children: [
          // 카메라 프리뷰 (비율 유지, contain으로 표시)
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.contain, // cover → contain (전체 이미지 표시)
              child: SizedBox(
                width: _cameraController!.value.previewSize!.height,
                height: _cameraController!.value.previewSize!.width,
                child: CameraPreview(_cameraController!),
              ),
            ),
          ),
          
          // 바운딩 박스 오버레이
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 카메라 프리뷰 크기 (90도 회전 후)
                final camWidth = _cameraController!.value.previewSize!.height;
                final camHeight = _cameraController!.value.previewSize!.width;
                
                // 화면에 표시되는 프리뷰 영역 계산 (contain 방식)
                final screenWidth = constraints.maxWidth;
                final screenHeight = constraints.maxHeight;
                
                final scaleX = screenWidth / camWidth;
                final scaleY = screenHeight / camHeight;
                final scale = scaleX < scaleY ? scaleX : scaleY;
                
                final displayWidth = camWidth * scale;
                final displayHeight = camHeight * scale;
                final offsetX = (screenWidth - displayWidth) / 2;
                final offsetY = (screenHeight - displayHeight) / 2;
                
                return CustomPaint(
                  painter: BoundingBoxPainter(
                    detections: _detections,
                    displayRect: Rect.fromLTWH(offsetX, offsetY, displayWidth, displayHeight),
                    cameraSize: Size(camWidth, camHeight),
                  ),
                );
              },
            ),
          ),
          
          // 하단 감지 결과 패널
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 150,
              color: Colors.black.withOpacity(0.8),
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
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _detections.length,
                      itemBuilder: (context, index) {
                        final det = _detections[index];
                        return Container(
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

/// CustomPainter: 바운딩 박스 그리기
class BoundingBoxPainter extends CustomPainter {
  final List<Detection> detections;
  final Rect displayRect; // 화면에 표시되는 프리뷰 영역
  final Size cameraSize; // 카메라 이미지 크기

  BoundingBoxPainter({
    required this.detections,
    required this.displayRect,
    required this.cameraSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Letterbox 패딩 계산 (640x640 내에서 이미지가 차지하는 영역)
    final camAspect = cameraSize.width / cameraSize.height;
    final targetAspect = 1.0; // 640x640 = 정사각형
    
    double padX = 0, padY = 0;
    double scaleInModel;
    
    if (camAspect > targetAspect) {
      // 이미지가 더 넓음 → 좌우에 여백 없음, 상하에 패딩
      scaleInModel = 640.0 / cameraSize.width;
      final newHeight = cameraSize.height * scaleInModel;
      padY = (640.0 - newHeight) / 2 / 640.0;
    } else {
      // 이미지가 더 높음 → 상하에 여백 없음, 좌우에 패딩
      scaleInModel = 640.0 / cameraSize.height;
      final newWidth = cameraSize.width * scaleInModel;
      padX = (640.0 - newWidth) / 2 / 640.0;
    }

    for (var detection in detections) {
      final bbox = detection.bbox;
      
      // 모델 출력 좌표 (0~1)에서 letterbox 패딩 제거
      double x1 = (bbox[0] - padX) / (1 - 2 * padX);
      double y1 = (bbox[1] - padY) / (1 - 2 * padY);
      double x2 = (bbox[2] - padX) / (1 - 2 * padX);
      double y2 = (bbox[3] - padY) / (1 - 2 * padY);
      
      // 범위 체크 (패딩 영역에 있는 객체는 무시)
      if (x1 > 1 || x2 < 0 || y1 > 1 || y2 < 0) continue;
      
      x1 = x1.clamp(0.0, 1.0);
      y1 = y1.clamp(0.0, 1.0);
      x2 = x2.clamp(0.0, 1.0);
      y2 = y2.clamp(0.0, 1.0);
      
      // 화면 좌표로 변환
      final screenX1 = displayRect.left + x1 * displayRect.width;
      final screenY1 = displayRect.top + y1 * displayRect.height;
      final screenX2 = displayRect.left + x2 * displayRect.width;
      final screenY2 = displayRect.top + y2 * displayRect.height;

      final rect = Rect.fromLTRB(screenX1, screenY1, screenX2, screenY2);
      canvas.drawRect(rect, paint);

      // 라벨 텍스트
      final textSpan = TextSpan(
        text: '${detection.label} ${(detection.confidence * 100).toStringAsFixed(0)}%',
        style: const TextStyle(
          color: Colors.red,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black87,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(screenX1, screenY1 > 20 ? screenY1 - 18 : screenY1 + 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
