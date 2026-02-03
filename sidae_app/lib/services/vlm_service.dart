import 'dart:async';
import 'dart:convert';
// import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'api_service.dart';

/// 태그 인식 결과
class TagRecognitionResult {
  final Uint8List imageBytes;
  final String response;
  final bool success;

  TagRecognitionResult({
    required this.imageBytes,
    required this.response,
    required this.success,
  });
}

/// VLM (Vision Language Model) 서비스
///
/// 태그 인식, 이미지 분석 등 VLM 관련 기능을 담당합니다.
class VlmService {
  // 싱글톤 패턴
  static final VlmService _instance = VlmService._internal();
  factory VlmService() => _instance;
  static VlmService get instance => _instance;
  VlmService._internal();

  static const MethodChannel _channel = MethodChannel(
    'com.ctrlcv.sidae_app/yolo_native',
  );

  // 스냅샷 콜백 (임시 저장)
  Function(Uint8List)? _snapshotCallback;

  /// 태그 인식 요청
  ///
  /// 현재 카메라 프레임을 캡처하여 API 서버로 전송합니다.
  /// Returns: TagRecognitionResult (이미지, 응답, 성공 여부)
  Future<TagRecognitionResult?> sendTagRecognition({
    required Function(Uint8List)? currentSnapshotCallback,
  }) async {
    try {
      // developer.log('🏷️ [VlmService] 태그 인식 시작', name: 'VlmService');

      final baseUrl = ApiService.baseUrl;
      final uri = Uri.parse('$baseUrl/bus-ai/bus-recognition');

      // 스냅샷 캡처
      // developer.log('📸 스냅샷 캡처 요청...', name: 'VlmService');

      final completer = Completer<Uint8List?>();

      // 스냅샷 콜백 설정
      _snapshotCallback = (imageBytes) {
        // developer.log(
        //   '📸 스냅샷 수신 (${imageBytes.length} bytes)',
        //   name: 'VlmService',
        // );
        if (!completer.isCompleted) {
          completer.complete(imageBytes);
        }
      };

      // 스냅샷 요청
      await _channel.invokeMethod('captureSnapshot');

      // 최대 5초 대기
      final imageBytes = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          // developer.log('⏱️ 스냅샷 캡처 타임아웃', name: 'VlmService');
          return null;
        },
      );

      // 콜백 복원
      _snapshotCallback = null;

      if (imageBytes == null) {
        // developer.log('❌ 이미지 데이터 없음', name: 'VlmService');
        return null;
      }

      // developer.log(
      //   '📸 프레임 캡처 완료 (${imageBytes.length} bytes)',
      //   name: 'VlmService',
      // );

      // API 서버로 전송
      final request = http.MultipartRequest('POST', uri)
        ..fields['mode'] = 'tag_'
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            imageBytes,
            filename: 'tag_recognition.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        );

      // developer.log('📤 태그 인식 요청 전송...', name: 'VlmService');

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          // developer.log('⏱️ 태그 인식 타임아웃', name: 'VlmService');
          throw TimeoutException('Tag recognition timeout');
        },
      );

      // developer.log(
      //   '📥 응답 수신: ${streamedResponse.statusCode}',
      //   name: 'VlmService',
      // );

      if (streamedResponse.statusCode == 200) {
        final response = await http.Response.fromStream(streamedResponse);
        final responseBody = utf8.decode(response.bodyBytes);
        // developer.log('✅ 태그 인식 성공: $responseBody', name: 'VlmService');

        return TagRecognitionResult(
          imageBytes: imageBytes,
          response: responseBody,
          success: true,
        );
      } else {
        final errorMsg = '서버 오류: ${streamedResponse.statusCode}';
        // developer.log(
        //   '❌ 태그 인식 실패: ${streamedResponse.statusCode}',
        //   name: 'VlmService',
        // );

        return TagRecognitionResult(
          imageBytes: imageBytes,
          response: errorMsg,
          success: false,
        );
      }
    } catch (e) {
      // developer.log('❌ 태그 인식 오류: $e', name: 'VlmService');
      return null;
    }
  }

  /// 스냅샷 이벤트 핸들러 (외부에서 호출)
  void handleSnapshotEvent(Uint8List imageBytes) {
    _snapshotCallback?.call(imageBytes);
  }

  /// VLM 더미 테스트 (개발용)
  Future<void> sendToVlmDummy(Uint8List imageBytes) async {
    // developer.log(
    //   '🧪 [VLM Dummy] 이미지 수신 (${imageBytes.length} bytes)',
    //   name: 'VlmService',
    // );
    await Future.delayed(const Duration(milliseconds: 1500));
    // developer.log(
    //   '✅ [VLM Dummy] 응답: "태그기를 찾았습니다!" (Confidence: 0.98)',
    //   name: 'VlmService',
    // );
  }
}
