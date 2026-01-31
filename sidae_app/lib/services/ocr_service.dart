import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'api_service.dart';

/// 버스 번호 OCR 결과
class OcrResult {
  final String busNumber;
  final String? carNumber;
  final int responseTimeMs;

  OcrResult({
    required this.busNumber,
    this.carNumber,
    required this.responseTimeMs,
  });

  String get displayText {
    if (carNumber != null) {
      return '버스: $busNumber / 차량: $carNumber';
    }
    return '버스: $busNumber';
  }
}

/// 버스 번호판 OCR 서비스
///
/// 크롭된 버스 이미지에서 번호판을 인식합니다.
class OcrService {
  // 싱글톤 패턴
  static final OcrService _instance = OcrService._internal();
  factory OcrService() => _instance;
  static OcrService get instance => _instance;
  OcrService._internal();

  bool _isSending = false;

  // 콜백
  Function(OcrResult result)? onBusNumberFound;

  /// OCR 요청 전송
  ///
  /// [imageBytes]: 크롭된 버스 이미지
  /// Returns: OcrResult or null
  Future<OcrResult?> sendOcrRequest(Uint8List imageBytes) async {
    if (_isSending) {
      developer.log('⏭️ OCR 요청 스킵 (이미 전송 중)', name: 'OcrService');
      return null;
    }
    _isSending = true;

    final stopwatch = Stopwatch()..start();

    try {
      final baseUrl = ApiService.baseUrl;
      final uri = Uri.parse('$baseUrl/bus-ai/bus-recognition');

      developer.log('🚀 OCR 요청 시작', name: 'OcrService');
      developer.log('  - URL: $uri', name: 'OcrService');
      developer.log(
        '  - 이미지 크기: ${imageBytes.length} bytes',
        name: 'OcrService',
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

      developer.log('📤 HTTP 요청 전송 중...', name: 'OcrService');

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          developer.log('⏱️ OCR 요청 타임아웃 (10초)', name: 'OcrService');
          throw TimeoutException('OCR request timeout');
        },
      );

      developer.log(
        '📥 응답 수신: ${streamedResponse.statusCode}',
        name: 'OcrService',
      );

      if (streamedResponse.statusCode == 200) {
        final response = await http.Response.fromStream(streamedResponse);
        final responseBody = utf8.decode(response.bodyBytes);
        developer.log('📄 응답 본문: $responseBody', name: 'OcrService');

        final jsonResponse = json.decode(responseBody);

        if (jsonResponse['status'] == 'success') {
          final result = jsonResponse['result'] as Map<String, dynamic>?;
          final busNumber = result?['bus_number'] as String?;

          // raw_text 폴백 처리
          String? extractedBusNumber = busNumber;
          String? extractedCarNumber;

          if ((busNumber == null || busNumber == 'null') && result != null) {
            final rawText = result['raw_text'] as String?;
            if (rawText != null && rawText.isNotEmpty) {
              extractedBusNumber = _extractBusNumber(rawText);
              extractedCarNumber = _extractCarNumber(rawText);
            }
          }

          if (extractedBusNumber != null && extractedBusNumber != 'null') {
            stopwatch.stop();
            final ocrResult = OcrResult(
              busNumber: extractedBusNumber,
              carNumber: extractedCarNumber,
              responseTimeMs: stopwatch.elapsedMilliseconds,
            );

            developer.log(
              '✅ OCR 성공: ${ocrResult.displayText} (${ocrResult.responseTimeMs}ms)',
              name: 'OcrService',
            );

            onBusNumberFound?.call(ocrResult);

            // 성공 시 2초 쿨다운
            await Future.delayed(const Duration(seconds: 2));
            return ocrResult;
          }
        }
      }
      return null;
    } catch (e, stackTrace) {
      developer.log(
        '💥 OCR 오류: $e',
        name: 'OcrService',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    } finally {
      _isSending = false;
      developer.log('🔓 OCR 요청 잠금 해제', name: 'OcrService');
    }
  }

  /// raw_text에서 버스 번호 추출
  String? _extractBusNumber(String rawText) {
    final busNumPattern = RegExp(r'bus_num:\s*(\d+)', caseSensitive: false);
    final busNumberPattern = RegExp(
      r'bus_number:\s*(\d+)',
      caseSensitive: false,
    );

    var match = busNumPattern.firstMatch(rawText);
    match ??= busNumberPattern.firstMatch(rawText);

    if (match != null && match.groupCount >= 1) {
      developer.log(
        '🔧 raw_text에서 버스 번호 추출: ${match.group(1)}',
        name: 'OcrService',
      );
      return match.group(1);
    }
    return null;
  }

  /// raw_text에서 차량 번호 추출
  String? _extractCarNumber(String rawText) {
    final carNumPattern = RegExp(r'car_num:\s*(\d+)', caseSensitive: false);
    final match = carNumPattern.firstMatch(rawText);

    if (match != null && match.groupCount >= 1) {
      developer.log(
        '🔧 raw_text에서 차량 번호 추출: ${match.group(1)}',
        name: 'OcrService',
      );
      return match.group(1);
    }
    return null;
  }

  /// 요청 중인지 확인
  bool get isSending => _isSending;
}
