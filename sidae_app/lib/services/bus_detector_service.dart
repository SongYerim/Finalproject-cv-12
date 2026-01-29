import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';

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
  static const EventChannel _eventChannel = EventChannel(
    'com.ctrlcv.sidae_app/yolo_detections',
  );

  StreamSubscription? _detectionSubscription;
  bool _isActive = false;

  // 콜백
  Function(BusDetection detection)? onBusDetected;
  Function(Uint8List croppedImage)? onBusCropped; // 현재 네이티브 모드에서 미지원
  Function(String status)? onStatusChanged;

  // 상태
  bool get isActive => _isActive;

  /// 감지 시작 (네이티브 카메라 + YOLO)
  Future<bool> startDetection() async {
    // 이미 활성화된 경우 재초기화하지 않음
    if (_isActive) {
      developer.log(
        '⚠️ [BusDetectorService] 이미 감지가 활성화되어 있습니다',
        name: 'BusDetectorService',
      );
      return true;
    }

    try {
      developer.log(
        '🎬 [BusDetectorService] startDetection() 시작',
        name: 'BusDetectorService',
      );
      _updateStatus('카메라 초기화 중...');

      // 1. 모델과 라벨 로드 (6.dart와 동일하게)
      const modelPath = 'assets/yolo11n_float16.tflite';
      developer.log('  - 모델 로드: $modelPath', name: 'BusDetectorService');
      final modelBytes = await rootBundle.load(modelPath);
      final labelsData = await rootBundle.loadString('assets/coco_labels.txt');

      // 2. 네이티브 초기화
      developer.log('  - 네이티브 초기화 중...', name: 'BusDetectorService');
      final initResult = await _channel.invokeMethod('initialize', {
        'modelBytes': modelBytes.buffer.asUint8List(),
        'labelsText': labelsData,
        'modelPath': modelPath,
      });

      if (initResult is! Map || initResult['initialized'] != true) {
        developer.log('  - ❌ 네이티브 초기화 실패', name: 'BusDetectorService');
        _updateStatus('네이티브 초기화 실패');
        return false;
      }

      // 3. EventChannel 구독
      developer.log('  - EventChannel 구독', name: 'BusDetectorService');
      _subscribeToDetections();

      // 4. 네이티브 카메라 시작
      developer.log('  - 네이티브 카메라 시작', name: 'BusDetectorService');
      await _channel.invokeMethod('startCamera');
      _updateStatus('버스 감지 시작');

      _isActive = true;
      developer.log(
        '✅ [BusDetectorService] startDetection() 완료',
        name: 'BusDetectorService',
      );
      return true;
    } catch (e) {
      developer.log(
        '❌ [BusDetectorService] 오류: $e',
        name: 'BusDetectorService',
      );
      _updateStatus('카메라 시작 실패: $e');
      return false;
    }
  }

  /// EventChannel에서 감지 결과 수신
  void _subscribeToDetections() {
    _detectionSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map && event.containsKey('detections')) {
          _handleDetections(event);
        }
      },
      onError: (error) {
        _updateStatus('감지 오류: $error');
      },
    );
  }

  /// 감지 결과 처리
  void _handleDetections(Map<dynamic, dynamic> event) {
    final detections = event['detections'] as List?;
    if (detections == null || detections.isEmpty) return;

    // 버스만 필터링 (label == 'bus')
    for (final det in detections) {
      if (det is Map) {
        final label = det['label'] as String?;
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

              // Note: 네이티브 모드에서는 Flutter 'camera' 패키지를 사용하지 않으므로
              // 현재 구조에서는 Dart 측에서 이미지 crop이 불가능합니다.
              // 필요 시 네이티브에서 crop된 이미지를 전달받도록 수정해야 합니다.
            }
          }
        }
      }
    }
  }

  void _updateStatus(String status) {
    onStatusChanged?.call(status);
  }

  /// 감지 중지
  Future<void> stopDetection() async {
    developer.log(
      '🛑 [BusDetectorService] stopDetection() 호출',
      name: 'BusDetectorService',
    );

    _isActive = false;

    // EventChannel 구독 취소
    if (_detectionSubscription != null) {
      developer.log('  - EventChannel 구독 취소 중...', name: 'BusDetectorService');
      await _detectionSubscription?.cancel();
      _detectionSubscription = null;
      developer.log('  - EventChannel 구독 취소 완료', name: 'BusDetectorService');
    }

    // 네이티브 카메라 중지 (타임아웃 2초)
    try {
      developer.log('  - 네이티브 카메라 중지 시작...', name: 'BusDetectorService');
      await _channel
          .invokeMethod('stopCamera')
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () {
              developer.log(
                '  - ⚠️ stopCamera 타임아웃 (2초)',
                name: 'BusDetectorService',
              );
              return null;
            },
          );
      developer.log('  - 네이티브 카메라 중지 완료', name: 'BusDetectorService');
    } catch (e) {
      developer.log('  - ⚠️ stopCamera 오류: $e', name: 'BusDetectorService');
    }

    _updateStatus('감지 중지됨');
    developer.log(
      '✅ [BusDetectorService] stopDetection() 완료',
      name: 'BusDetectorService',
    );
  }

  Future<void> dispose() async {
    developer.log(
      '🗑️ [BusDetectorService] dispose() 호출',
      name: 'BusDetectorService',
    );
    await stopDetection();
    developer.log(
      '✅ [BusDetectorService] dispose() 완료',
      name: 'BusDetectorService',
    );
  }
}
