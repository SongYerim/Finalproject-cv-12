import 'dart:async';
// import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/services.dart';
import 'ocr_service.dart';
import 'vlm_service.dart';
import 'api_service.dart';
import 'shared_event_channel.dart';

// TagRecognitionResult를 vlm_service.dart에서 re-export
export 'vlm_service.dart' show TagRecognitionResult;

/// 버스 감지 결과
class BusDetection {
  final String label;
  final double confidence;
  final List<double> bbox; // [x1, y1, x2, y2] - 정규화된 좌표 (0~1)

  BusDetection({
    required this.label,
    required this.confidence,
    required this.bbox,
  });

  factory BusDetection.fromMap(Map<dynamic, dynamic> map) {
    return BusDetection(
      label: map['label'] as String,
      confidence: (map['confidence'] as num).toDouble(),
      bbox: (map['bbox'] as List).map((e) => (e as num).toDouble()).toList(),
    );
  }

  @override
  String toString() =>
      'BusDetection($label, ${(confidence * 100).toStringAsFixed(1)}%, bbox: $bbox)';
}

/// 버스 인식 서비스
///
/// 네이티브 YOLO + EventChannel을 통해 버스를 감지합니다.
/// Flutter의 camera 패키지 대신 네이티브 카메라(AndroidView)를 활용합니다.
class BusDetectorService {
  static const MethodChannel _channel = MethodChannel(
    'com.ctrlcv.sidae_app/yolo_native',
  );

  StreamSubscription? _detectionSubscription;
  bool _isActive = false;

  // OCR 및 VLM 서비스 인스턴스
  final OcrService _ocrService = OcrService.instance;
  final VlmService _vlmService = VlmService.instance;

  // 콜백
  Function(BusDetection detection)? onBusDetected;
  Function(Uint8List croppedImage)? onBusCropped; // 현재 네이티브 모드에서 미지원
  Function(String status)? onStatusChanged;
  Function(String busNumber, int responseTimeMs)?
  onBusNumberFound; // OCR 결과 + 응답시간 콜백
  Function(Uint8List fullImage)? onSnapshotCaptured; // 스냅샷 콜백

  // 상태
  bool get isActive => _isActive;

  /// 감지 시작 (네이티브 카메라 + YOLO)
  Future<bool> startDetection() async {
    // 이미 활성화된 경우 재초기화하지 않음
    if (_isActive) {
      // developer.log(
      //   '⚠️ [BusDetectorService] 이미 감지가 활성화되어 있습니다',
      //   name: 'BusDetectorService',
      // );
      return true;
    }

    try {
      // developer.log(
      //   '🎬 [BusDetectorService] startDetection() 시작',
      //   name: 'BusDetectorService',
      // );
      _updateStatus('카메라 초기화 중...');

      // 1. 모델과 라벨 로드 (6.dart와 동일하게)
      const modelPath = 'assets/yolo11s_float16.tflite';
      // developer.log('  - 모델 로드: $modelPath', name: 'BusDetectorService');
      final modelBytes = await rootBundle.load(modelPath);
      final labelsData = await rootBundle.loadString('assets/coco_labels.txt');

      // 2. 네이티브 초기화
      // developer.log('  - 네이티브 초기화 중...', name: 'BusDetectorService');
      final initResult = await _channel.invokeMethod('initialize', {
        'modelBytes': modelBytes.buffer.asUint8List(),
        'labelsText': labelsData,
        'modelPath': modelPath,
      });

      if (initResult is! Map || initResult['initialized'] != true) {
        // developer.log('  - ❌ 네이티브 초기화 실패', name: 'BusDetectorService');
        _updateStatus('네이티브 초기화 실패');
        return false;
      }

      // 3. EventChannel 구독
      // developer.log('  - EventChannel 구독', name: 'BusDetectorService');
      _subscribeToDetections();

      // 4. 네이티브 카메라 시작
      // developer.log('  - 네이티브 카메라 시작', name: 'BusDetectorService');
      await _channel.invokeMethod('startCamera');
      _updateStatus('버스 감지 시작');

      _isActive = true;
      // developer.log(
      //   '✅ [BusDetectorService] startDetection() 완료',
      //   name: 'BusDetectorService',
      // );
      return true;
    } catch (e) {
      // developer.log(
      //   '❌ [BusDetectorService] 오류: $e',
      //   name: 'BusDetectorService',
      // );
      _updateStatus('카메라 시작 실패: $e');
      return false;
    }
  }

  /// EventChannel에서 감지 결과 수신 (SharedEventChannel 사용)
  void _subscribeToDetections() {
    _detectionSubscription = SharedEventChannel.instance.stream.listen(
      (event) {
        if (event is Map) {
          if (event['type'] == 'snapshot') {
            final imageBytes = event['image'] as Uint8List?;
            if (imageBytes != null) {
              // developer.log(
              //   '📸 [BusDetectorService] 스냅샷 수신 (${imageBytes.length} bytes)',
              //   name: 'BusDetectorService',
              // );
              onSnapshotCaptured?.call(imageBytes);
            }
          } else if (event.containsKey('detections')) {
            _handleDetections(event);
          }
        }
      },
      onError: (error) {
        _updateStatus('감지 오류: $error');
      },
    );
  }

  /// 스냅샷 캡쳐 요청 (전체 화면)
  Future<void> requestSnapshot() async {
    if (!_isActive) return;
    try {
      await _channel.invokeMethod('captureSnapshot');
    } catch (e) {
      // developer.log('❌ 스냅샷 요청 실패: $e', name: 'BusDetectorService');
    }
  }

  /// VLM 서버 전송 시뮬레이션 (Dummy) - VlmService로 위임
  Future<void> sendToVlmDummy(Uint8List imageBytes) async {
    await _vlmService.sendToVlmDummy(imageBytes);
  }

  /// 태그 인식 요청 (mode: tag_) - 네이티브 업로드 방식 사용
  ///
  /// 네이티브에서 캡처 및 업로드를 직접 수행하여 타임아웃 문제를 방지합니다.
  /// Returns: TagRecognitionResult (이미지, 응답, 성공 여부)
  Future<TagRecognitionResult?> sendTagRecognition() async {
    if (!_isActive) {
      // developer.log(
      //   '⚠️ [BusDetectorService] 카메라가 활성화되지 않음',
      //   name: 'BusDetectorService',
      // );
      return null;
    }

    try {
      final baseUrl = ApiService.baseUrl;
      final uploadUrl = '$baseUrl/bus-ai/bus-recognition';

      // developer.log(
      //   '📤 [BusDetectorService] 태그 인식 요청 (Native) - URL: $uploadUrl',
      //   name: 'BusDetectorService',
      // );

      // 네이티브 메서드 호출
      final result = await _channel.invokeMethod('captureAndUploadImage', {
        'uploadUrl': uploadUrl,
        'jpegQuality': 90,
        'metadata': {'source': 'bus_detector', 'mode': 'tag_'},
        'keepFile': true, // 결과 이미지 표시를 위해 파일 유지
      });

      if (result is Map) {
        final localPath = result['localPath'] as String?;
        final body = result['body'] as String?;

        Uint8List? imageBytes;

        // 로컬 파일에서 이미지 바이트 읽기
        if (localPath != null) {
          try {
            final file = File(localPath);
            if (await file.exists()) {
              imageBytes = await file.readAsBytes();
              // 필요하다면 파일 삭제 (지금은 유지)
              // await file.delete();
            }
          } catch (e) {
            // developer.log('⚠️ 이미지 파일 읽기 실패: $e', name: 'BusDetectorService');
          }
        }

        // developer.log(
        //   '✅ [BusDetectorService] 태그 인식 성공 (응답: $body)',
        //   name: 'BusDetectorService',
        // );

        return TagRecognitionResult(
          imageBytes: imageBytes ?? Uint8List(0), // 이미지가 없으면 빈 바이트
          response: body ?? '',
          success: true,
        );
      } else {
        // developer.log(
        //   '❌ [BusDetectorService] 예상치 못한 결과 형식: $result',
        //   name: 'BusDetectorService',
        // );
        return null;
      }
    } catch (e) {
      // developer.log(
      //   '❌ [BusDetectorService] 태그 인식 실패: $e',
      //   name: 'BusDetectorService',
      // );
      return null;
    }
  }

  /// 감지 결과 처리
  void _handleDetections(Map<dynamic, dynamic> event) {
    // 1. 크롭된 이미지 처리
    final croppedImage = event['croppedImage'] as Uint8List?;
    if (croppedImage != null) {
      // developer.log(
      //   '📸 [BusDetectorService] 크롭 이미지 수신 (크기: ${croppedImage.length} bytes)',
      //   name: 'BusDetectorService',
      // );
      onBusCropped?.call(croppedImage);

      // OCR 서버 전송 - OcrService로 위임
      _sendCroppedImageViaOcrService(croppedImage);
    }

    // 2. 감지된 객체 처리
    final detections = event['detections'] as List?;
    if (detections == null || detections.isEmpty) return;

    // 버스만 필터링 (label == 'bus')
    for (final det in detections) {
      if (det is Map) {
        final label = (det['label'] as String?)?.trim();
        if (label != null && label == 'bus') {
          final confidence = (det['confidence'] as num?)?.toDouble() ?? 0.0;

          // 신뢰도 50% 이상만 처리
          if (confidence >= 0.5) {
            final bbox = det['bbox'] as List?;
            if (bbox != null && bbox.length >= 4) {
              final busDetection = BusDetection(
                label: label,
                confidence: confidence,
                bbox: bbox.map((e) => (e as num).toDouble()).toList(),
              );

              onBusDetected?.call(busDetection);
            }
          }
        }
      }
    }
  }

  /// 서버로 크롭된 이미지 전송 (OCR) - OcrService로 위임
  Future<void> _sendCroppedImageViaOcrService(Uint8List imageBytes) async {
    final result = await _ocrService.sendOcrRequest(imageBytes);

    if (result != null) {
      // developer.log(
      //   '✅ OCR 성공: ${result.displayText} (${result.responseTimeMs}ms)',
      //   name: 'BusDetectorService',
      // );
      onBusNumberFound?.call(result.displayText, result.responseTimeMs);
    }
  }

  /// YOLO 추론 중지 (카메라는 유지)
  Future<void> stopInference() async {
    try {
      await _channel.invokeMethod('setInferenceEnabled', {'enabled': false});
      // developer.log('🧠 YOLO 추론 중지됨', name: 'BusDetectorService');
    } catch (e) {
      // developer.log('❌ 추론 중지 실패: $e', name: 'BusDetectorService');
    }
  }

  void _updateStatus(String status) {
    onStatusChanged?.call(status);
  }

  /// 감지 중지
  Future<void> stopDetection() async {
    // developer.log(
    //   '🛑 [BusDetectorService] stopDetection() 호출',
    //   name: 'BusDetectorService',
    // );

    _isActive = false;

    // EventChannel 구독 취소
    if (_detectionSubscription != null) {
      // developer.log('  - EventChannel 구독 취소 중...', name: 'BusDetectorService');
      await _detectionSubscription?.cancel();
      _detectionSubscription = null;
      // developer.log('  - EventChannel 구독 취소 완료', name: 'BusDetectorService');
    }

    // 네이티브 카메라 중지 (타임아웃 2초)
    try {
      // developer.log('  - 네이티브 카메라 중지 시작...', name: 'BusDetectorService');
      await _channel
          .invokeMethod('stopCamera')
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () {
              // developer.log(
              //   '  - ⚠️ stopCamera 타임아웃 (2초)',
              //   name: 'BusDetectorService',
              // );
              return null;
            },
          );
      // developer.log('  - 네이티브 카메라 중지 완료', name: 'BusDetectorService');
    } catch (e) {
      // developer.log('  - ⚠️ stopCamera 오류: $e', name: 'BusDetectorService');
    }

    _updateStatus('감지 중지됨');
    // developer.log(
    //   '✅ [BusDetectorService] stopDetection() 완료',
    //   name: 'BusDetectorService',
    // );
  }

  Future<void> dispose() async {
    // developer.log(
    //   '🗑️ [BusDetectorService] dispose() 호출',
    //   name: 'BusDetectorService',
    // );
    await stopDetection();
    // developer.log(
    //   '✅ [BusDetectorService] dispose() 완료',
    //   name: 'BusDetectorService',
    // );
  }
}
