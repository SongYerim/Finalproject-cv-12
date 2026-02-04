// import 'dart:developer' as developer;
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:porcupine_flutter/porcupine_error.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class PorcupineService {
  static PorcupineService? _instance;
  static PorcupineService get instance => _instance ??= PorcupineService._();
  PorcupineService._();

  PorcupineManager? _porcupineManager;
  bool _isInitialized = false;
  bool _isStarted = false;
  Function(String)? onKeywordDetected;

  Future<bool> initialize() async {
    // print('🔍 [Porcupine] initialize() 호출됨 - _isInitialized: $_isInitialized');
    if (_isInitialized) {
      // print('✅ [Porcupine] 이미 초기화됨');
      // developer.log('✅ [Porcupine] 이미 초기화됨', name: 'Porcupine');
      // developer.log('📊 [Porcupine] 현재 상태 - isStarted: $_isStarted, onKeywordDetected: ${onKeywordDetected != null ? "등록됨" : "null"}', name: 'Porcupine');
      return true;
    }

    try {
      // 마이크 권한 확인 및 요청
      // print('🔐 [Porcupine] 마이크 권한 확인 시작');
      // developer.log('🔐 [Porcupine] 마이크 권한 확인 시작', name: 'Porcupine');

      // 현재 권한 상태 확인
      final currentStatus = await Permission.microphone.status;
      // print('📊 [Porcupine] 현재 마이크 권한 상태: $currentStatus');
      // developer.log('📊 [Porcupine] 현재 마이크 권한 상태: $currentStatus', name: 'Porcupine');

      if (currentStatus.isDenied) {
        // print('🔐 [Porcupine] 마이크 권한 요청 중...');
        // developer.log('🔐 [Porcupine] 마이크 권한 요청 중...', name: 'Porcupine');
        final micStatus = await Permission.microphone.request();
        // print('📊 [Porcupine] 마이크 권한 요청 결과: $micStatus');
        // developer.log('📊 [Porcupine] 마이크 권한 요청 결과: $micStatus', name: 'Porcupine');

        if (!micStatus.isGranted) {
          // print('❌ [Porcupine] 마이크 권한이 거부되었습니다. 상태: $micStatus');
          // developer.log('❌ [Porcupine] 마이크 권한이 거부되었습니다. 상태: $micStatus', name: 'Porcupine');
          return false;
        }
      } else if (currentStatus.isPermanentlyDenied) {
        // print('❌ [Porcupine] 마이크 권한이 영구적으로 거부되었습니다.');
        // developer.log('❌ [Porcupine] 마이크 권한이 영구적으로 거부되었습니다. 설정에서 수동으로 허용해야 합니다.', name: 'Porcupine');
        return false;
      } else if (currentStatus.isGranted) {
        // print('✅ [Porcupine] 마이크 권한이 이미 허용되어 있습니다');
        // developer.log('✅ [Porcupine] 마이크 권한이 이미 허용되어 있습니다', name: 'Porcupine');
      }

      // .env에서 Porcupine Access Key 가져오기
      final accessKey = dotenv.env['PORCUPINE_KEY'];
      // print('🔑 [Porcupine] PORCUPINE_KEY 확인: ${accessKey != null ? "존재함 (길이: ${accessKey.length})" : "null"}');
      if (accessKey == null || accessKey.isEmpty) {
        // print('❌ [Porcupine] PORCUPINE_KEY가 .env 파일에 설정되지 않았습니다');
        // developer.log('❌ [Porcupine] PORCUPINE_KEY가 .env 파일에 설정되지 않았습니다', name: 'Porcupine');
        return false;
      }

      // print('🔧 [Porcupine] PorcupineManager.fromKeywordPaths() 호출 시작');
      // developer.log('🔧 [Porcupine] 초기화 시작', name: 'Porcupine');

      // PorcupineManager 초기화 (커스텀 키워드 파일 사용)
      // sidae_ko_android_v4_0_0.ppn은 한국어 키워드 파일
      // porcupine_params_ko.pv는 한국어 모델 파일
      // print('📁 [Porcupine] 키워드 파일: assets/sidae_ko_android_v4_0_0.ppn (한국어)');
      // print('📁 [Porcupine] 모델 파일: assets/porcupine_params_ko.pv (한국어)');
      _porcupineManager = await PorcupineManager.fromKeywordPaths(
        accessKey,
        ['assets/sidae_ko_android_v4_0_0.ppn'],
        _wakeWordCallback,
        modelPath: 'assets/porcupine_params_ko.pv', // 한국어 모델 경로
        errorCallback: _errorCallback,
      );

      _isInitialized = true;
      // print('✅ [Porcupine] 초기화 완료');
      // developer.log('✅ [Porcupine] 초기화 완료', name: 'Porcupine');
      return true;
    } on PorcupineException {
      // print('❌ [Porcupine] 초기화 실패 (PorcupineException): ${e.message}');
      // developer.log('❌ [Porcupine] 초기화 실패: ${e.message}', name: 'Porcupine', error: e);
      return false;
    } catch (_) {
      // print('❌ [Porcupine] 초기화 실패 (일반 예외): $e');
      // print('❌ [Porcupine] 스택 트레이스: $stackTrace');
      // developer.log('❌ [Porcupine] 초기화 실패: $e', name: 'Porcupine', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// 키워드 감지 콜백
  void _wakeWordCallback(int keywordIndex) {
    // developer.log('✅ [Porcupine] 키워드 감지됨 (인덱스: $keywordIndex)', name: 'Porcupine');
    // developer.log('📞 [Porcupine] onKeywordDetected 콜백 호출: ${onKeywordDetected != null ? "등록됨" : "null"}', name: 'Porcupine');
    if (onKeywordDetected != null) {
      try {
        onKeywordDetected!('시대야');
        // developer.log('✅ [Porcupine] onKeywordDetected 콜백 실행 완료', name: 'Porcupine');
      } catch (e, stackTrace) {
        // developer.log('❌ [Porcupine] onKeywordDetected 콜백 실행 실패: $e', name: 'Porcupine', error: e, stackTrace: stackTrace);
      }
    } else {
      // developer.log('⚠️ [Porcupine] onKeywordDetected가 null입니다. 콜백이 등록되지 않았습니다.', name: 'Porcupine');
    }
  }

  /// 에러 콜백
  /// 에러 콜백
  void _errorCallback(PorcupineException error) {
    // print('❌ [Porcupine] 에러 발생: ${error.message}');
    // developer.log('❌ [Porcupine] 에러 발생: ${error.message}', name: 'Porcupine', error: error);

    // 에러 발생 시 Porcupine이 중지될 수 있으므로 재시작 시도
    _isStarted = false; // 상태 리셋
    // print('🔄 [Porcupine] 에러로 인해 상태 리셋, 재시작 시도');

    // 비동기로 재시작 시도 (에러 콜백 내에서 직접 await 불가)
    Future.delayed(const Duration(milliseconds: 500), () async {
      if (_isInitialized && !_isStarted) {
        // print('🔄 [Porcupine] 자동 재시작 시도');
        final restarted = await start();
        if (restarted) {
          // print('✅ [Porcupine] 자동 재시작 성공');
        } else {
          // print('❌ [Porcupine] 자동 재시작 실패');
        }
      }
    });
  }

  Future<bool> start() async {
    if (_isStarted) {
      // developer.log('✅ [Porcupine] 이미 시작됨', name: 'Porcupine');
      return true;
    }

    if (!_isInitialized) {
      // developer.log('⚠️ [Porcupine] 초기화되지 않음, 초기화 시도', name: 'Porcupine');
      final initialized = await initialize();
      if (!initialized) {
        // developer.log('❌ [Porcupine] 초기화 실패로 인해 시작할 수 없습니다', name: 'Porcupine');
        return false;
      }
    }

    // 마이크 권한 재확인
    final micStatus = await Permission.microphone.status;
    // developer.log('📊 [Porcupine] start() 호출 시 마이크 권한 상태: $micStatus', name: 'Porcupine');
    if (!micStatus.isGranted) {
      // developer.log('⚠️ [Porcupine] 마이크 권한이 없어 권한 재요청', name: 'Porcupine');
      final requestedStatus = await Permission.microphone.request();
      // developer.log('📊 [Porcupine] 권한 재요청 결과: $requestedStatus', name: 'Porcupine');
      if (!requestedStatus.isGranted) {
        // developer.log('❌ [Porcupine] 마이크 권한이 없어 시작할 수 없습니다', name: 'Porcupine');
        return false;
      }
    }

    if (_porcupineManager == null) {
      // developer.log('❌ [Porcupine] PorcupineManager가 null입니다', name: 'Porcupine');
      return false;
    }

    try {
      // developer.log('🎤 [Porcupine] PorcupineManager.start() 호출 전', name: 'Porcupine');
      // developer.log('🎤 [Porcupine] PorcupineManager 상태: ${_porcupineManager.runtimeType}', name: 'Porcupine');
      await _porcupineManager!.start();
      _isStarted = true;
      // developer.log('✅ [Porcupine] 키워드 감지 시작 완료 - 마이크 활성화됨', name: 'Porcupine');
      return true;
    } on PorcupineException {
      // developer.log('❌ [Porcupine] 시작 실패 (PorcupineException): ${e.message}', name: 'Porcupine', error: e);
      return false;
    } catch (_) {
      // developer.log('❌ [Porcupine] 시작 실패: $e', name: 'Porcupine', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  Future<void> stop() async {
    if (!_isStarted) {
      // print('⚠️ [Porcupine] 이미 중지됨');
      // developer.log('⚠️ [Porcupine] 이미 중지됨', name: 'Porcupine');
      return;
    }

    try {
      // print('🛑 [Porcupine] PorcupineManager.stop() 호출');
      // developer.log('🛑 [Porcupine] PorcupineManager.stop() 호출', name: 'Porcupine');
      await _porcupineManager?.stop();
      _isStarted = false;
      // print('✅ [Porcupine] 키워드 감지 중지');
      // developer.log('✅ [Porcupine] 키워드 감지 중지', name: 'Porcupine');
    } on PorcupineException {
      // print('❌ [Porcupine] 중지 실패: ${e.message}');
      // developer.log('❌ [Porcupine] 중지 실패: ${e.message}', name: 'Porcupine', error: e);
      _isStarted = false;
    } catch (e) {
      // print('❌ [Porcupine] 중지 실패: $e');
      // developer.log('❌ [Porcupine] 중지 실패: $e', name: 'Porcupine', error: e);
      _isStarted = false;
    }
  }

  /// Porcupine이 실행 중인지 확인하고, 중지되어 있으면 재시작
  /// 카메라 종료 후 호출하여 Porcupine이 계속 작동하도록 보장
  Future<void> ensureRunning() async {
    // print('🔍 [Porcupine] ensureRunning() 호출 - _isInitialized: $_isInitialized, _isStarted: $_isStarted');
    // developer.log('🔍 [Porcupine] ensureRunning() 호출 - _isInitialized: $_isInitialized, _isStarted: $_isStarted', name: 'Porcupine');

    if (!_isInitialized) {
      // print('⚠️ [Porcupine] 초기화되지 않음, 초기화 시도');
      // developer.log('⚠️ [Porcupine] 초기화되지 않음, 초기화 시도', name: 'Porcupine');
      final initialized = await initialize();
      if (!initialized) {
        // print('❌ [Porcupine] 초기화 실패');
        // developer.log('❌ [Porcupine] 초기화 실패', name: 'Porcupine');
        return;
      }
    }

    // 카메라 종료 후 Porcupine이 중지되었을 수 있으므로
    // _isStarted가 true여도 강제로 재시작하여 안정성 확보
    if (!_isStarted) {
      // print('🔄 [Porcupine] 중지되어 있음, 재시작 시도');
      // developer.log('🔄 [Porcupine] 중지되어 있음, 재시작 시도', name: 'Porcupine');
    } else {
      // print('🔄 [Porcupine] 상태는 시작됨이지만, 카메라 종료 후 안정성을 위해 재시작');
      // developer.log('🔄 [Porcupine] 상태는 시작됨이지만, 카메라 종료 후 안정성을 위해 재시작', name: 'Porcupine');
      // 기존 인스턴스를 중지하고 재시작
      try {
        await _porcupineManager?.stop();
        _isStarted = false;
        // print('✅ [Porcupine] 기존 인스턴스 중지 완료');
      } catch (e) {
        // print('⚠️ [Porcupine] 기존 인스턴스 중지 실패 (무시): $e');
        _isStarted = false;
      }
    }

    // 약간의 지연 후 재시작 (오디오 리소스 해제 시간 확보)
    await Future.delayed(const Duration(milliseconds: 300));

    final started = await start();
    if (started) {
      // print('✅ [Porcupine] ensureRunning() 완료 - Porcupine 재시작 성공');
      // developer.log('✅ [Porcupine] ensureRunning() 완료 - Porcupine 재시작 성공', name: 'Porcupine');
    } else {
      // print('❌ [Porcupine] ensureRunning() 실패 - Porcupine 재시작 실패');
      // developer.log('❌ [Porcupine] ensureRunning() 실패 - Porcupine 재시작 실패', name: 'Porcupine');
    }
  }

  Future<void> dispose() async {
    await stop();
    try {
      await _porcupineManager?.delete();
      _porcupineManager = null;
      _isInitialized = false;
      // developer.log('✅ [Porcupine] 리소스 해제 완료', name: 'Porcupine');
    } catch (e) {
      // developer.log('❌ [Porcupine] 리소스 해제 실패: $e', name: 'Porcupine', error: e);
    }
  }
}
