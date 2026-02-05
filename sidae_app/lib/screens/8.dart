import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/route_tracker.dart';
import '../services/tts_service.dart';
import '../services/porcupine_service.dart';
import '../services/shared_event_channel.dart';

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
  int? _responseTimeMs; // 응답 시간 (밀리초)
  Timer? _previewTimer;
  StreamSubscription? _exitDistanceSubscription;
  StreamSubscription? _sttSubscription; // STT 구독 추가
  final PorcupineService _porcupineService = PorcupineService.instance;
  bool _hasArrived = false; // 중복 하차 처리 방지 플래그
  String? _capturedVlmPrompt; // STT 결과 저장
  Completer<String>? _sttResultCompleter; // STT 결과를 기다리는 Completer
  bool _isListeningStt = false; // STT 진행 중 여부
  String _sttText = ''; // STT 텍스트 (partial 및 final)

  static const MethodChannel _channel = MethodChannel(
    'com.ctrlcv.sidae_app/yolo_native',
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

  // STT 초기화 함수
  void _initStt() {
    try {
      _sttSubscription = SharedEventChannel.instance.stream.listen((event) {
        if (event is Map && event['type'] == 'stt') {
          final eventType = event['eventType'] as String?;
          final data = event['data'] as String?;

          switch (eventType) {
            case 'partial':
              // 부분 결과 업데이트
              if (mounted && _isListeningStt) {
                setState(() {
                  _sttText = data ?? '';
                });
              }
              break;
            case 'result':
              // 최종 결과
              if (mounted && _sttResultCompleter != null && !_sttResultCompleter!.isCompleted) {
                setState(() {
                  _capturedVlmPrompt = data ?? '';
                  _sttText = data ?? '';
                  // _isListeningStt는 2초 후에 false로 설정
                });
                _sttResultCompleter!.complete(data ?? '');
                
                // 최종 결과를 2초간 표시한 후 오버레이 숨김
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) {
                    setState(() {
                      _isListeningStt = false;
                    });
                  }
                });
              }
              break;
            case 'error':
              if (mounted && _sttResultCompleter != null && !_sttResultCompleter!.isCompleted) {
                setState(() {
                  _isListeningStt = false;
                  _sttText = '';
                });
                TtsService.instance.speak("음성인식에 실패했습니다. 다시 시도해주세요.");
                _sttResultCompleter!.complete('');
              }
              break;
          }
        }
      });
    } catch (e) {
      developer.log('❌ [8.dart] STT 초기화 실패: $e', name: 'STT');
    }
  }

  // VLM 모드로 이미지 캡처 및 업로드 (카메라와 STT 동시 시작)
  Future<void> _captureAndUploadVLM(BuildContext context) async {
    final stopwatch = Stopwatch()..start();

    try {
      // 카메라 권한 확인 및 요청
      final cameraStatus = await Permission.camera.status;
      if (!cameraStatus.isGranted) {
        final result = await Permission.camera.request();
        if (!result.isGranted) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('카메라 권한이 필요합니다. 설정에서 권한을 허용해주세요.'),
              ),
            );
          }
          return;
        }
      }

      if (mounted) {
        setState(() {
          _lastResponse = 'No response';
          _responseTimeMs = null;
          _capturedVlmPrompt = null;
        });
      }

      // STT 결과를 기다리는 Completer 생성
      _sttResultCompleter = Completer<String>();

      // Porcupine 중지 및 TTS 중지
      await TtsService.instance.stop();
      await _porcupineService.stop();

      // STT 시작
      if (mounted) {
        setState(() {
          _isListeningStt = true;
          _sttText = '';
        });
        await TtsService.instance.speak("말씀하세요");
      }

      try {
        await _channel.invokeMethod('startListening');
      } catch (e) {
        developer.log('❌ [8.dart] STT 시작 실패: $e', name: 'STT');
        if (mounted) {
          setState(() {
            _isListeningStt = false;
          });
          TtsService.instance.speak("음성인식 시작에 실패했습니다.");
        }
        _sttResultCompleter!.complete('');
      }

      // 카메라 캡처를 백그라운드에서 시작 (STT와 동시에 시작)
      // 하지만 업로드는 STT 결과를 기다린 후에 하도록 변경
      final baseUrl = dotenv.env['SIDAE_SERVER_CLOUD_URL'];
      if (baseUrl == null || baseUrl.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('SIDAE_SERVER_CLOUD_URL이 설정되지 않았습니다.'),
            ),
          );
        }
        return;
      }

      final uploadUrl = '$baseUrl/bus-ai/bus-recognition';

      // STT 결과를 기다림 (최대 10초)
      final sttResult = await _sttResultCompleter!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          developer.log('⏱️ [8.dart] STT 타임아웃', name: 'STT');
          // 타임아웃 시 오버레이 즉시 숨김
          if (mounted) {
            setState(() {
              _isListeningStt = false;
            });
          }
          return '';
        },
      );

      // STT 중지
      try {
        await _channel.invokeMethod('stopListening');
      } catch (_) {}
      
      // 정상적인 경우는 case 'result'에서 2초 후에 _isListeningStt = false로 설정됨
      // 타임아웃의 경우는 onTimeout에서 처리됨

      // STT 결과를 metadata에 포함하여 카메라 캡처 및 업로드
      final metadata = <String, String>{
        'source': 'vlm',
        'mode': 'vlm',
      };
      
      if (sttResult.isNotEmpty) {
        metadata['vlm_prompt'] = sttResult;
        developer.log('📝 [8.dart] STT 결과를 vlm_prompt로 포함: $sttResult', name: 'STT');
      }

      // 카메라 캡처 및 업로드 (vlm_prompt 포함)
      final result = await _channel.invokeMethod('captureAndUploadImage', {
        'uploadUrl': uploadUrl,
        'jpegQuality': 90,
        'metadata': metadata,
        'keepFile': true,
      });

      if (result is Map) {
        stopwatch.stop();
        final responseTime = stopwatch.elapsedMilliseconds;

        final path = result['localPath'];
        var body = result['body'];

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
            _responseTimeMs = responseTime;
          });
        }

        // 응답에서 description 파싱하여 TTS로 읽기 (먼저 처리)
        if (body != null) {
          try {
            final bodyStr = body.toString();
            developer.log('📥 [8.dart] VLM 응답 수신: $bodyStr', name: 'VLM');

            final jsonResponse = json.decode(bodyStr);
            developer.log('✅ [8.dart] JSON 파싱 성공: $jsonResponse', name: 'VLM');

            // description 추출 시도 (두 가지 형태 지원)
            String? description;

            // 형태 1: {"description": "..."}
            if (jsonResponse is Map && jsonResponse['description'] != null) {
              description = jsonResponse['description'].toString();
              developer.log(
                '📝 [8.dart] description 추출 (직접): $description',
                name: 'VLM',
              );
            }
            // 형태 2: {"result": {"description": "..."}}
            else if (jsonResponse is Map && jsonResponse['result'] != null) {
              final result = jsonResponse['result'];
              if (result is Map && result['description'] != null) {
                description = result['description'].toString();
                developer.log(
                  '📝 [8.dart] description 추출 (result 내부): $description',
                  name: 'VLM',
                );
              }
            }

            if (description != null && description.isNotEmpty) {
              developer.log(
                '🔊 [8.dart] TTS 호출 시작: "$description"',
                name: 'VLM',
              );
              // TTS 초기화 보장
              await TtsService.instance.initialize();
              // TTS는 비동기로 시작 (카메라 종료를 기다리지 않음)
              TtsService.instance.speak(description).catchError((e) {
                developer.log('❌ [8.dart] TTS 호출 실패: $e', name: 'VLM');
              });
              developer.log('✅ [8.dart] TTS 호출 완료', name: 'VLM');
            } else {
              developer.log(
                '⚠️ [8.dart] description을 찾을 수 없음. JSON 구조: $jsonResponse',
                name: 'VLM',
              );
            }
          } catch (e) {
            // JSON 파싱 실패 시 무시 (기존 동작 유지)
            developer.log('❌ [8.dart] VLM 응답 파싱 실패: $e', name: 'VLM');
          }
        } else {
          developer.log('⚠️ [8.dart] 응답 body가 없음', name: 'VLM');
        }

        // TTS 시작 후 카메라 종료 (await하여 완료 보장)
        try {
          await _channel.invokeMethod('stopCamera');
          developer.log('✅ [8.dart] 카메라 종료 완료', name: 'VLM');
          print('✅ [8.dart] 카메라 종료 완료');
        } catch (e) {
          developer.log('❌ [8.dart] 카메라 종료 실패: $e', name: 'VLM');
          print('❌ [8.dart] 카메라 종료 실패: $e');
        }

        // 카메라 종료 후 Porcupine이 계속 실행되도록 보장
        // 약간의 지연을 두어 오디오 리소스가 완전히 해제되도록 함
        await Future.delayed(const Duration(milliseconds: 500));

        try {
          print('🔄 [8.dart] Porcupine 재시작 시작');
          developer.log('🔄 [8.dart] Porcupine 재시작 시작', name: 'Porcupine');
          await _porcupineService.ensureRunning();
          print('✅ [8.dart] Porcupine 재시작 완료');
          developer.log('✅ [8.dart] Porcupine 재시작 완료', name: 'Porcupine');
        } catch (e, stackTrace) {
          print('❌ [8.dart] Porcupine 재시작 실패: $e');
          developer.log(
            '❌ [8.dart] Porcupine 재시작 실패: $e',
            name: 'Porcupine',
            error: e,
            stackTrace: stackTrace,
          );
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

  Future<void> _captureAndUpload(BuildContext context, String source) async {
    // 시작 시간 측정
    final stopwatch = Stopwatch()..start();

    try {
      // 카메라 권한 확인 및 요청
      final cameraStatus = await Permission.camera.status;
      if (!cameraStatus.isGranted) {
        final result = await Permission.camera.request();
        if (!result.isGranted) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('카메라 권한이 필요합니다. 설정에서 권한을 허용해주세요.'),
              ),
            );
          }
          return;
        }
        // 권한 요청 후 약간의 지연 (권한 상태 업데이트 대기)
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (mounted) {
        setState(() {
          _lastResponse = 'No response';
          _responseTimeMs = null; // 이전 시간 초기화
        });
      }

      // source에 따라 mode 설정
      // 하차벨: 'stop_bell' -> mode: 'bell'
      // 교통카드 태그기: 'card_tagger' -> mode: 'tags_'
      final mode = source == 'stop_bell' ? 'bell' : 'tag';

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
      try {
        await _channel.invokeMethod('stopCamera');
        developer.log('✅ [8.dart] 카메라 종료 완료 (하차벨/태그기)', name: 'Camera');
        print('✅ [8.dart] 카메라 종료 완료 (하차벨/태그기)');
      } catch (e) {
        developer.log('❌ [8.dart] 카메라 종료 실패: $e', name: 'Camera');
        print('❌ [8.dart] 카메라 종료 실패: $e');
      }

      // 카메라 종료 후 Porcupine이 계속 실행되도록 보장
      // 약간의 지연을 두어 오디오 리소스가 완전히 해제되도록 함
      await Future.delayed(const Duration(milliseconds: 500));

      try {
        print('🔄 [8.dart] Porcupine 재시작 시작 (하차벨/태그기)');
        developer.log(
          '🔄 [8.dart] Porcupine 재시작 시작 (하차벨/태그기)',
          name: 'Porcupine',
        );
        await _porcupineService.ensureRunning();
        print('✅ [8.dart] Porcupine 재시작 완료 (하차벨/태그기)');
        developer.log(
          '✅ [8.dart] Porcupine 재시작 완료 (하차벨/태그기)',
          name: 'Porcupine',
        );
      } catch (e, stackTrace) {
        print('❌ [8.dart] Porcupine 재시작 실패 (하차벨/태그기): $e');
        developer.log(
          '❌ [8.dart] Porcupine 재시작 실패 (하차벨/태그기): $e',
          name: 'Porcupine',
          error: e,
          stackTrace: stackTrace,
        );
      }

      if (result is Map) {
        stopwatch.stop(); // 응답 받은 시점에 타이머 중지
        final responseTime = stopwatch.elapsedMilliseconds;

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
            _responseTimeMs = responseTime; // 응답 시간 저장
          });
        }

        // 응답에서 des와 reason 파싱하여 TTS로 읽기
        if (body != null) {
          try {
            final bodyStr = body.toString();
            developer.log(
              '📥 [8.dart] 하차벨/태그기 응답 수신: $bodyStr',
              name: 'BusAction',
            );
            print('📥 [8.dart] 하차벨/태그기 응답 수신: $bodyStr');

            final jsonResponse = json.decode(bodyStr);
            developer.log(
              '✅ [8.dart] JSON 파싱 성공: $jsonResponse',
              name: 'BusAction',
            );

            // des와 reason 추출 시도 (두 가지 형태 지원)
            String? des;
            String? reason;

            // 형태 1: {"des": "...", "reason": "..."}
            if (jsonResponse is Map) {
              if (jsonResponse['des'] != null) {
                des = jsonResponse['des'].toString();
                developer.log(
                  '📝 [8.dart] des 추출 (직접): $des',
                  name: 'BusAction',
                );
              }
              if (jsonResponse['reason'] != null) {
                reason = jsonResponse['reason'].toString();
                developer.log(
                  '📝 [8.dart] reason 추출 (직접): $reason',
                  name: 'BusAction',
                );
              }

              // 형태 2: {"result": {"des": "...", "reason": "..."}}
              if ((des == null || reason == null) &&
                  jsonResponse['result'] != null) {
                final result = jsonResponse['result'];
                if (result is Map) {
                  if (des == null && result['des'] != null) {
                    des = result['des'].toString();
                    developer.log(
                      '📝 [8.dart] des 추출 (result 내부): $des',
                      name: 'BusAction',
                    );
                  }
                  if (reason == null && result['reason'] != null) {
                    reason = result['reason'].toString();
                    developer.log(
                      '📝 [8.dart] reason 추출 (result 내부): $reason',
                      name: 'BusAction',
                    );
                  }
                }
              }
            }

            // des와 reason을 이어서 TTS로 읽기
            if (des != null || reason != null) {
              final List<String> parts = [];
              if (des != null && des.isNotEmpty) {
                parts.add(des);
              }
              if (reason != null && reason.isNotEmpty) {
                parts.add(reason);
              }

              if (parts.isNotEmpty) {
                final ttsText = parts.join('. ');
                developer.log(
                  '🔊 [8.dart] TTS 호출 시작: "$ttsText"',
                  name: 'BusAction',
                );
                print('🔊 [8.dart] TTS 호출 시작: "$ttsText"');

                // TTS 초기화 보장
                await TtsService.instance.initialize();

                // TTS는 비동기로 시작
                TtsService.instance.speak(ttsText).catchError((e) {
                  developer.log('❌ [8.dart] TTS 호출 실패: $e', name: 'BusAction');
                  print('❌ [8.dart] TTS 호출 실패: $e');
                });
                developer.log('✅ [8.dart] TTS 호출 완료', name: 'BusAction');
                print('✅ [8.dart] TTS 호출 완료');
              } else {
                developer.log(
                  '⚠️ [8.dart] des와 reason이 모두 비어있음',
                  name: 'BusAction',
                );
                print('⚠️ [8.dart] des와 reason이 모두 비어있음');
              }
            } else {
              developer.log(
                '⚠️ [8.dart] des와 reason을 찾을 수 없음. JSON 구조: $jsonResponse',
                name: 'BusAction',
              );
              print('⚠️ [8.dart] des와 reason을 찾을 수 없음. JSON 구조: $jsonResponse');
            }
          } catch (e, stackTrace) {
            // JSON 파싱 실패 시 무시 (기존 동작 유지)
            developer.log(
              '❌ [8.dart] 하차벨/태그기 응답 파싱 실패: $e',
              name: 'BusAction',
              error: e,
              stackTrace: stackTrace,
            );
            print('❌ [8.dart] 하차벨/태그기 응답 파싱 실패: $e');
          }
        } else {
          developer.log('⚠️ [8.dart] 응답 body가 없음', name: 'BusAction');
          print('⚠️ [8.dart] 응답 body가 없음');
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
      try {
        await _channel.invokeMethod('stopCamera');
        developer.log('✅ [8.dart] 카메라 종료 완료 (에러 처리)', name: 'Camera');
        print('✅ [8.dart] 카메라 종료 완료 (에러 처리)');
      } catch (stopError) {
        developer.log('❌ [8.dart] 카메라 종료 실패: $stopError', name: 'Camera');
        print('❌ [8.dart] 카메라 종료 실패: $stopError');
      }

      // 에러 발생 시에도 Porcupine 재시작
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        print('🔄 [8.dart] Porcupine 재시작 시작 (에러 처리)');
        developer.log(
          '🔄 [8.dart] Porcupine 재시작 시작 (에러 처리)',
          name: 'Porcupine',
        );
        await _porcupineService.ensureRunning();
        print('✅ [8.dart] Porcupine 재시작 완료 (에러 처리)');
        developer.log('✅ [8.dart] Porcupine 재시작 완료 (에러 처리)', name: 'Porcupine');
      } catch (porcupineError) {
        print('❌ [8.dart] Porcupine 재시작 실패 (에러 처리): $porcupineError');
        developer.log(
          '❌ [8.dart] Porcupine 재시작 실패 (에러 처리): $porcupineError',
          name: 'Porcupine',
        );
      }

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
    print('🚀 [8.dart] initState() 시작');
    developer.log('🚀 [8.dart] initState() 시작', name: '8.dart');

    _initStt(); // STT 초기화 추가

    try {
      _startNativeReturnTrackingIfNeeded();
      print('✅ [8.dart] _startNativeReturnTrackingIfNeeded() 완료');
    } catch (e, stackTrace) {
      print('❌ [8.dart] _startNativeReturnTrackingIfNeeded() 에러: $e');
      developer.log(
        '❌ [8.dart] _startNativeReturnTrackingIfNeeded() 에러: $e',
        name: '8.dart',
        error: e,
        stackTrace: stackTrace,
      );
    }

    // Porcupine 초기화 및 시작 (비동기로 실행)
    print('🚀 [8.dart] _initPorcupine() 호출 예정');
    developer.log('🚀 [8.dart] _initPorcupine() 호출 예정', name: 'Porcupine');
    _initPorcupine().catchError((e, stackTrace) {
      print('❌ [8.dart] _initPorcupine() 에러: $e');
      developer.log(
        '❌ [8.dart] _initPorcupine() 에러: $e',
        name: 'Porcupine',
        error: e,
        stackTrace: stackTrace,
      );
    });
  }

  Future<void> _initPorcupine() async {
    try {
      print('🔧 [8.dart] Porcupine 초기화 시작');
      developer.log('🔧 [8.dart] Porcupine 초기화 시작', name: 'Porcupine');

      // 콜백을 먼저 설정 (initialize 전에)
      _porcupineService.onKeywordDetected = (keyword) {
        print('📞 [8.dart] onKeywordDetected 콜백 호출됨: $keyword');
        developer.log(
          '📞 [8.dart] onKeywordDetected 콜백 호출됨: $keyword',
          name: 'Porcupine',
        );
        if (keyword == '시대야' && mounted) {
          print('🎤 [8.dart] "시대야" 키워드 감지됨 - VLM 호출 시작');
          developer.log(
            '🎤 [8.dart] "시대야" 키워드 감지됨 - VLM 호출 시작',
            name: 'Porcupine',
          );
          _captureAndUploadVLM(context);
        } else {
          print(
            '⚠️ [8.dart] 키워드 불일치 또는 화면이 마운트되지 않음: keyword=$keyword, mounted=$mounted',
          );
          developer.log(
            '⚠️ [8.dart] 키워드 불일치 또는 화면이 마운트되지 않음: keyword=$keyword, mounted=$mounted',
            name: 'Porcupine',
          );
        }
      };
      print('✅ [8.dart] onKeywordDetected 콜백 등록 완료');
      developer.log('✅ [8.dart] onKeywordDetected 콜백 등록 완료', name: 'Porcupine');

      print('🔧 [8.dart] PorcupineService.initialize() 호출');
      developer.log(
        '🔧 [8.dart] PorcupineService.initialize() 호출',
        name: 'Porcupine',
      );
      final initialized = await _porcupineService.initialize();

      if (initialized) {
        print('✅ [8.dart] Porcupine 초기화 성공, start() 호출');
        developer.log(
          '✅ [8.dart] Porcupine 초기화 성공, start() 호출',
          name: 'Porcupine',
        );
        final started = await _porcupineService.start();
        if (started) {
          print('✅ [8.dart] Porcupine 시작 완료 - 마이크 활성화됨');
          developer.log(
            '✅ [8.dart] Porcupine 시작 완료 - 마이크 활성화됨',
            name: 'Porcupine',
          );
        } else {
          print('❌ [8.dart] Porcupine 시작 실패');
          developer.log('❌ [8.dart] Porcupine 시작 실패', name: 'Porcupine');
        }
      } else {
        print('❌ [8.dart] Porcupine 초기화 실패');
        developer.log('❌ [8.dart] Porcupine 초기화 실패', name: 'Porcupine');
      }
    } catch (e, stackTrace) {
      print('❌ [8.dart] _initPorcupine() 예외 발생: $e');
      print('❌ [8.dart] 스택 트레이스: $stackTrace');
      developer.log(
        '❌ [8.dart] _initPorcupine() 예외 발생: $e',
        name: 'Porcupine',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _startNativeReturnTrackingIfNeeded() async {
    final lat = widget.returnMidLat;
    final lng = widget.returnMidLng;
    final threshold = widget.returnDistanceMeters;

    print(
      '🚌 [8.dart] Exit 추적 초기화 시작 - lat: $lat, lng: $lng, threshold: $threshold',
    );

    if (lat == null || lng == null) return;

    // 안전한 초기화를 위해 기존 추적 중지 및 딜레이
    await _channel.invokeMethod('stopExitTracking');
    await Future.delayed(const Duration(milliseconds: 500));

    // 공유 브로드캐스트 스트림 사용 - 취소해도 네이티브 onCancel 안 됨
    _exitDistanceSubscription = SharedEventChannel.instance.stream.listen(
      (event) {
        if (event is Map && event['type'] == 'exitDistance') {
          final distance = event['distance'];
          final reached = event['reached'] as bool? ?? false;

          // 거리 로그 출력 (디버깅용)
          print(
            '📍 [8.dart] 남은 거리: $distance m (목표: $threshold m) - 도달: $reached',
          );

          if (reached) {
            // 이미 하차 처리가 되었다면 중복 실행 방지
            if (_hasArrived) return;
            _hasArrived = true;

            print('🎉 [8.dart] 하차 지점 도달 확인! 종료 프로세스 시작');
            if (mounted) {
              // 버스 하차 상태 설정 (도보 경로 감지 재활성화)
              RouteTracker.instance.setOnBus(false);
              // TTS 안내
              TtsService.instance.speak('하차 완료. 도보로 전환합니다.');
              Navigator.of(context).pop();
            }
          }
        }
      },
      onError: (e) {
        print('❌ [8.dart] 이벤트 에러: $e');
      },
    );

    try {
      await _channel.invokeMethod('startExitTracking', {
        'exitLat': lat,
        'exitLng': lng,
        'exitThreshold': threshold,
      });
      print('✅ [8.dart] 네이티브 추적 시작 명령 전송 완료');
    } catch (e) {
      print('❌ [8.dart] 추적 시작 실패: $e');
    }
  }

  @override
  void dispose() {
    // Porcupine 중지하지 않음 (다른 화면에서도 사용 중일 수 있음)
    // 대신 콜백만 제거
    _porcupineService.onKeywordDetected = null;
    developer.log('🛑 [8.dart] Porcupine 콜백 제거 (화면 종료)', name: 'Porcupine');
    _previewTimer?.cancel();
    _previewTimer = null;
    _exitDistanceSubscription?.cancel();
    _exitDistanceSubscription = null;
    _sttSubscription?.cancel(); // STT 구독 취소
    _sttSubscription = null;
    _channel.invokeMethod('stopListening').catchError((_) {}); // STT 중지
    _channel.invokeMethod('stopExitTracking').catchError((_) {});
    _channel.invokeMethod('stopCamera').catchError((_) {});
    // 버스 하차 상태 설정 (dispose 시에도 보장)
    RouteTracker.instance.setOnBus(false);
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
            // 시대야 버튼 (오른쪽 윗부분)
            Positioned(
              top: 12,
              right: 12,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _captureAndUploadVLM(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD400),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        '시대야',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // STT 진행 중 오버레이
            if (_isListeningStt)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.9),
                    border: Border(
                      bottom: BorderSide(
                        color: const Color(0xFFFFD400),
                        width: 2,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '시대에게 어떤 질문을 하고 싶으신가요?',
                        style: TextStyle(
                          color: Color(0xFFFFD400),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_sttText.isNotEmpty)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 150),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade900,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.grey.shade700,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.mic,
                                color: Color(0xFFFFD400),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: Text(
                                    _sttText,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                    softWrap: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Row(
                          children: [
                            const Icon(
                              Icons.mic,
                              color: Color(0xFFFFD400),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '듣고 있어요...',
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 16,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            if (_lastImagePath != null)
              Positioned(
                left: 16,
                right: 16,
                top: _isListeningStt ? 120 : 12,
                child: AspectRatio(
                  aspectRatio: 3 / 4, // 카메라 비율 (일반적인 세로 모드)
                  child: Container(
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
                          // 응답 시간 표시 (우상단)
                          if (_responseTimeMs != null)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFD400),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '응답 시간: ${_responseTimeMs}ms',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
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
