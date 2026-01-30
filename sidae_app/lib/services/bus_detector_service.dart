import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart'; // MediaType
import '../services/api_service.dart';

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
  bool _isSending = false; // OCR 요청 중복 방지 플래그

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
      const modelPath = 'assets/yolo11s_float16.tflite';
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
        if (event is Map) {
          if (event['type'] == 'snapshot') {
            final imageBytes = event['image'] as Uint8List?;
            if (imageBytes != null) {
              developer.log(
                '📸 [BusDetectorService] 스냅샷 수신 (${imageBytes.length} bytes)',
                name: 'BusDetectorService',
              );
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
      developer.log('❌ 스냅샷 요청 실패: $e', name: 'BusDetectorService');
    }
  }

  /// VLM 서버 전송 시뮬레이션 (Dummy)
  Future<void> sendToVlmDummy(Uint8List imageBytes) async {
    developer.log(
      '🚀 [VLM] 서버로 이미지 전송 중... (${imageBytes.length} bytes)',
      name: 'BusDetectorService',
    );

    // 네트워킹 지연 시뮬레이션 (1~2초)
    await Future.delayed(const Duration(milliseconds: 1500));

    developer.log(
      '✅ [VLM] 응답 수신: "태그기를 찾았습니다!" (Confidence: 0.98)',
      name: 'BusDetectorService',
    );
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

      // OCR 서버 전송
      _sendCroppedImage(croppedImage);
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

  /// 서버로 크롭된 이미지 전송 (VLM)
  Future<void> _sendCroppedImage(Uint8List imageBytes) async {
    if (_isSending) {
      developer.log('⏭️ VLM 요청 스킵 (이미 전송 중)', name: 'BusDetectorService');
      return;
    }
    _isSending = true;

    // 시작 시간 측정
    final stopwatch = Stopwatch()..start();

    try {
      final baseUrl = ApiService.baseUrl;
      final uri = Uri.parse('$baseUrl/bus-ai/bus-recognition');

      developer.log('🚀 VLM 요청 시작', name: 'BusDetectorService');
      developer.log('  - URL: $uri', name: 'BusDetectorService');
      developer.log(
        '  - 이미지 크기: ${imageBytes.length} bytes',
        name: 'BusDetectorService',
      );

      final request = http.MultipartRequest('POST', uri)
        ..fields['mode'] = 'bus_number'
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            imageBytes,
            filename: 'bus_crop.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        );

      developer.log('📤 HTTP 요청 전송 중...', name: 'BusDetectorService');

      // 타임아웃 10초 (VLM 처리 시간 고려)
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          developer.log('⏱️ VLM 요청 타임아웃 (10초)', name: 'BusDetectorService');
          throw TimeoutException('VLM request timeout');
        },
      );

      developer.log(
        '📥 응답 수신: ${streamedResponse.statusCode}',
        name: 'BusDetectorService',
      );

      if (streamedResponse.statusCode == 200) {
        final response = await http.Response.fromStream(streamedResponse);
        final responseBody = utf8.decode(response.bodyBytes);

        developer.log('📄 응답 본문: $responseBody', name: 'BusDetectorService');

        final jsonResponse = json.decode(responseBody);
        developer.log('🔍 JSON 파싱 성공', name: 'BusDetectorService');
        developer.log(
          '  - status: ${jsonResponse['status']}',
          name: 'BusDetectorService',
        );
        developer.log(
          '  - mode: ${jsonResponse['mode']}',
          name: 'BusDetectorService',
        );

        if (jsonResponse['status'] == 'success') {
          final result = jsonResponse['result'] as Map<String, dynamic>?;
          developer.log('  - result: $result', name: 'BusDetectorService');

          final busNumber = result?['bus_number'] as String?;
          developer.log(
            '  - bus_number: $busNumber',
            name: 'BusDetectorService',
          );

          // raw_text 폴백 처리 (VLM이 잘못된 JSON을 반환한 경우)
          String? extractedBusNumber = busNumber;
          String? extractedCarNumber;

          if ((busNumber == null || busNumber == 'null') && result != null) {
            final rawText = result['raw_text'] as String?;
            developer.log('  - raw_text: $rawText', name: 'BusDetectorService');

            if (rawText != null && rawText.isNotEmpty) {
              // {bus_num: 370, car_num: 5040} 형식에서 숫자 추출
              final busNumPattern = RegExp(
                r'bus_num:\s*(\d+)',
                caseSensitive: false,
              );
              final busNumberPattern = RegExp(
                r'bus_number:\s*(\d+)',
                caseSensitive: false,
              );
              final carNumPattern = RegExp(
                r'car_num:\s*(\d+)',
                caseSensitive: false,
              );

              // 버스 번호 추출
              var match = busNumPattern.firstMatch(rawText);
              if (match == null) {
                match = busNumberPattern.firstMatch(rawText);
              }

              if (match != null && match.groupCount >= 1) {
                extractedBusNumber = match.group(1);
                developer.log(
                  '🔧 raw_text에서 버스 번호 추출: $extractedBusNumber',
                  name: 'BusDetectorService',
                );
              }

              // 차량 번호 추출
              final carMatch = carNumPattern.firstMatch(rawText);
              if (carMatch != null && carMatch.groupCount >= 1) {
                extractedCarNumber = carMatch.group(1);
                developer.log(
                  '🔧 raw_text에서 차량 번호 추출: $extractedCarNumber',
                  name: 'BusDetectorService',
                );
              }
            }
          }

          if (extractedBusNumber != null && extractedBusNumber != 'null') {
            stopwatch.stop(); // 응답 수신 시점
            final responseTime = stopwatch.elapsedMilliseconds;

            // 버스 번호와 차량 번호를 포함한 결과 문자열 생성
            String resultText = '버스: $extractedBusNumber';
            if (extractedCarNumber != null && extractedCarNumber != 'null') {
              resultText += ' / 차량: $extractedCarNumber';
            }

            developer.log(
              '✅ VLM OCR 성공: $resultText (응답시간: ${responseTime}ms)',
              name: 'BusDetectorService',
            );
            developer.log(
              '📞 콜백 호출: onBusNumberFound',
              name: 'BusDetectorService',
            );
            onBusNumberFound?.call(resultText, responseTime);

            // 성공 시 2초 쿨다운
            await Future.delayed(const Duration(seconds: 2));
          } else {
            developer.log('⚠️ 버스 번호 인식 실패 (null)', name: 'BusDetectorService');
          }
        } else {
          developer.log(
            '❌ VLM 응답 실패: ${jsonResponse['status']}',
            name: 'BusDetectorService',
          );
        }
      } else {
        final errorBody = await streamedResponse.stream.bytesToString();
        developer.log(
          '❌ HTTP 오류 ${streamedResponse.statusCode}: $errorBody',
          name: 'BusDetectorService',
        );
      }
    } catch (e, stackTrace) {
      developer.log(
        '💥 VLM 오류: $e',
        name: 'BusDetectorService',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      // 응답 완료 후 플래그 해제
      _isSending = false;
      developer.log('🔓 VLM 요청 잠금 해제', name: 'BusDetectorService');
    }
  }

  /// YOLO 추론 중지 (카메라는 유지)
  Future<void> stopInference() async {
    try {
      await _channel.invokeMethod('setInferenceEnabled', {'enabled': false});
      developer.log('🧠 YOLO 추론 중지됨', name: 'BusDetectorService');
    } catch (e) {
      developer.log('❌ 추론 중지 실패: $e', name: 'BusDetectorService');
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
    _isSending = false;

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
