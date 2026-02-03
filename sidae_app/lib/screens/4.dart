import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/route_model.dart';
import '../services/route_tracker.dart';
import '../services/crosswalk_detector.dart';
import '../services/bus_stop_detector.dart';
import '../services/bus_arrival_service.dart';
import '../services/bus_popup_state_service.dart';
import '../services/tts_service.dart';
import '../services/porcupine_service.dart';
import '9.dart';
import '../services/navigation_service.dart';
import '../widgets/progress_indicator_widget.dart';
import '../widgets/bus_arrival_overlay.dart';
import '../widgets/route_timeline_widget.dart';
import '../utils/bus_utils.dart' as bus_utils;
import '../utils/math_utils.dart' as math_utils;
import '5.dart';
import '6.dart';
import '7.dart';

class Screen4 extends StatefulWidget {
  final List<RouteSegment> routes;
  final String destinationName;

  const Screen4({
    super.key,
    required this.routes,
    required this.destinationName,
  });

  @override
  State<Screen4> createState() => _Screen4State();
}

class _Screen4State extends State<Screen4> {
  final RouteTracker _tracker = RouteTracker.instance;
  final NavigationService _navService = NavigationService.instance;
  final TtsService _ttsService = TtsService.instance;
  final PorcupineService _porcupineService = PorcupineService.instance;
  final BusPopupStateService _popupState = BusPopupStateService.instance;
  final BusArrivalService _busArrivalService = BusArrivalService.instance;
  CrosswalkDetector? _crosswalkDetector;
  BusStopDetector? _busStopDetector;
  bool _isNavigatingToCrosswalk = false; // 카메라 중복 실행 방지 플래그

  static const MethodChannel _channel = MethodChannel(
    'com.ctrlcv.sidae_app/yolo_native',
  );

  double _distanceToTarget = 0.0;
  DateTime _lastVibrationTime = DateTime.now();

  // 360-0 wrap-around 처리를 위한 이전 각도
  double _prevTargetAngle = 0.0;
  double _prevCurrentAngle = 0.0;

  // _isBusApproachingStatus -> bus_utils.isBusApproachingStatus 로 이동됨

  @override
  void initState() {
    super.initState();
    _initializePathPoints();
    _initCrosswalkDetector();
    _initBusStopDetector();
    _ttsService.initialize();
    _navService.initSensor();

    // 센서 방향 업데이트 시 UI 갱신 (60Hz)
    _navService.onBearingUpdate = () {
      if (mounted) {
        setState(() {}); // 센서 데이터 변경 시 즉시 UI 갱신
      }
    };

    // 팝업 상태 변경 리스너 등록
    _popupState.onStateChanged = () {
      if (mounted) {
        setState(() {}); // 팝업 상태 변경 시 UI 갱신
      }
    };

    // 단계 변경 TTS 콜백 등록
    _tracker.onStepChanged = (segmentIndex, stepIndex, description) {
      if (mounted) {
        _ttsService.speak(description);
        setState(() {});
      }
    };

    // 도착 완료 콜백 등록
    _tracker.onRouteCompleted = () {
      if (!mounted) return;
      HapticFeedback.vibrate();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ArrivalScreen(destinationName: widget.destinationName),
        ),
      );
    };

    _navService.startLocationTracking(onUpdate: _onPositionUpdate);

    // 초기 안내 (화면 진입 시)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tracker.announceInitialStep();
    });

    // Porcupine 초기화 및 시작 (비동기로 실행)
    developer.log('🚀 [4.dart] _initPorcupine() 호출 예정', name: 'Porcupine');
    _initPorcupine().catchError((e, stackTrace) {
      developer.log(
        '❌ [4.dart] _initPorcupine() 에러: $e',
        name: 'Porcupine',
        error: e,
        stackTrace: stackTrace,
      );
    });
  }

  Future<void> _initPorcupine() async {
    try {
      developer.log('🔧 [4.dart] Porcupine 초기화 시작', name: 'Porcupine');

      // 콜백을 먼저 설정 (initialize 전에)
      _porcupineService.onKeywordDetected = (keyword) {
        developer.log(
          '📞 [4.dart] onKeywordDetected 콜백 호출됨: $keyword',
          name: 'Porcupine',
        );
        if (keyword == '시대야' && mounted) {
          developer.log(
            '🎤 [4.dart] "시대야" 키워드 감지됨 - VLM 호출 시작',
            name: 'Porcupine',
          );
          _captureAndUploadVLM(context);
        } else {
          developer.log(
            '⚠️ [4.dart] 키워드 불일치 또는 화면이 마운트되지 않음: keyword=$keyword, mounted=$mounted',
            name: 'Porcupine',
          );
        }
      };
      developer.log('✅ [4.dart] onKeywordDetected 콜백 등록 완료', name: 'Porcupine');

      developer.log(
        '🔧 [4.dart] PorcupineService.initialize() 호출',
        name: 'Porcupine',
      );
      final initialized = await _porcupineService.initialize();

      if (initialized) {
        developer.log(
          '✅ [4.dart] Porcupine 초기화 성공, start() 호출',
          name: 'Porcupine',
        );
        final started = await _porcupineService.start();
        if (started) {
          developer.log(
            '✅ [4.dart] Porcupine 시작 완료 - 마이크 활성화됨',
            name: 'Porcupine',
          );
        } else {
          developer.log('❌ [4.dart] Porcupine 시작 실패', name: 'Porcupine');
        }
      } else {
        developer.log('❌ [4.dart] Porcupine 초기화 실패', name: 'Porcupine');
      }
    } catch (e, stackTrace) {
      developer.log(
        '❌ [4.dart] _initPorcupine() 예외 발생: $e',
        name: 'Porcupine',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _initializePathPoints() {
    // 이미 초기화되었으면 건너뛰기 (Screen5에서 돌아온 경우)
    if (_tracker.allPathPoints.isNotEmpty) return;

    List<NLatLng> allPathPoints = [];
    for (var route in widget.routes) {
      allPathPoints.addAll(route.pathCoordinates);
    }
    if (allPathPoints.isNotEmpty) {
      _tracker.initialize(allPathPoints, routeSegments: widget.routes);
    }
  }

  void _initCrosswalkDetector() {
    _crosswalkDetector = CrosswalkDetector(
      routes: widget.routes,
      onCrosswalkDetected: (CrosswalkInfo crosswalkInfo) async {
        if (_isNavigatingToCrosswalk) return; // 이미 카메라로 이동 중이면 무시
        _isNavigatingToCrosswalk = true; // 플래그 설정

        if (!mounted) return;
        await _ttsService.speak("횡단보도 앞입니다. 카메라를 신호등쪽으로 돌려주세요.");
        HapticFeedback.vibrate();
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => YoloTestScreen(
              exitLat: crosswalkInfo.exitLat,
              exitLng: crosswalkInfo.exitLng,
            ),
          ),
        ).then((_) {
          // 카메라에서 돌아오면 콜백 재등록
          if (mounted) {
            _isNavigatingToCrosswalk = false;
            // 센서 재시작 및 콜백 재등록
            _navService.ensureSensorRunning();
          }
        });
      },
    );
  }

  void _onPositionUpdate(Position position) {
    if (!mounted) return;
    _checkCrosswalk(position);
    _checkBusStop(position);
    _checkAndUpdatePassedPoints(position);
    _distanceToTarget = _navService.getDistanceToTarget(position);
    _checkDirectionAndVibrate();
    setState(() {});
  }

  @override
  void dispose() {
    // Porcupine 중지하지 않음 (다른 화면에서도 사용 중일 수 있음)
    // 대신 콜백만 제거
    _porcupineService.onKeywordDetected = null;
    developer.log('🛑 [4.dart] Porcupine 콜백 제거 (화면 종료)', name: 'Porcupine');
    // NavigationService는 싱글톤 인스턴스로 dispose 하면 안 됨
    // _navService.dispose(); 제거
    super.dispose();
  }

  // 횡단보도 근접 감지
  void _checkCrosswalk(Position position) {
    if (_isNavigatingToCrosswalk) return; // 이미 카메라로 이동 중이면 체크하지 않음
    if (_crosswalkDetector == null) return;
    _crosswalkDetector!.checkCrosswalkProximity(position);
  }

  // 버스 정류장 근접 감지
  void _checkBusStop(Position position) {
    if (_popupState.isNavigatingToBusStop) return;
    if (_busStopDetector == null) return;
    _busStopDetector!.checkBusStopProximity(position);
  }

  // 버스 정류장 감지기 초기화
  void _initBusStopDetector() {
    _busStopDetector = BusStopDetector(
      routes: widget.routes,
      onBusStopDetected: (BusStopInfo busStopInfo) async {
        if (_popupState.isNavigatingToBusStop) return;

        if (!mounted) return;
        await _ttsService.speak("버스 정류장에 도착했습니다.");
        HapticFeedback.vibrate();

        // 버스 도착 정보 오버레이 표시 (전역 상태)
        _popupState.openPopup(busStopInfo.stationName);

        // 버스 도착 정보 조회 시작
        _busArrivalService.onArrivalUpdate = (arrival) {
          if (!mounted) return;
          // BusPopupStateService로 데이터 업데이트 (모든 화면에서 공유)
          _popupState.updateBusArrival(arrival);
          if (arrival != null) {
            // 응답이 올 때마다 오버레이 다시 표시 (사용자가 닫아도 자동으로 다시 켜짐)
            _popupState.openPopup(busStopInfo.stationName);
          }
          if (arrival != null) {
            _ttsService.speak("${arrival.busNumber}번 버스, ${arrival.statusMsg}");

            // "곧 도착" 상태 감지 시 BusArrivalScreen으로 화면 전환
            if (bus_utils.isBusApproachingStatus(arrival.statusMsg)) {
              // 곧 도착 상태일 때 추적 종료
              _busArrivalService.stopTracking();
              _closeBusArrivalOverlay();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => BusArrivalScreen(
                    busNumber: arrival.busNumber,
                    stationName: busStopInfo.stationName,
                    enableCamera: true, // 카메라 모드 활성화
                    exitLat: busStopInfo.exitLat, // 버스 하차 지점
                    exitLng: busStopInfo.exitLng,
                  ),
                ),
              ).then((_) {
                // 버스 탑승 화면에서 돌아오면
                if (mounted) {
                  _popupState.closePopup();
                  // 센서 재시작
                  _navService.ensureSensorRunning();
                }
              });
            }
          }
        };
        await _busArrivalService.startTracking(
          busStopInfo.busNumber,
          busStopInfo.stationName,
        );
      },
    );
  }

  // 버스 도착 오버레이 닫기 (추적은 계속)
  void _closeBusArrivalOverlay() {
    // stopTracking() 호출 제거 - 팝업 닫어도 백그라운드에서 계속 갱신
    _popupState.closePopup();
  }

  // 버스 도착 정보 오버레이 위젯 -> BusArrivalOverlay로 이동됨
  Widget _buildBusArrivalOverlay() {
    return BusArrivalOverlay(
      popupState: _popupState,
      onClose: _closeBusArrivalOverlay,
    );
  }

  // VLM 모드로 이미지 캡처 및 업로드
  Future<void> _captureAndUploadVLM(BuildContext context) async {
    try {
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

      final result = await _channel.invokeMethod('captureAndUploadImage', {
        'uploadUrl': uploadUrl,
        'jpegQuality': 90,
        'metadata': {'source': 'vlm', 'mode': 'vlm'},
        'keepFile': true,
      });

      // 응답에서 description 파싱하여 TTS로 읽기 (먼저 처리)
      if (result is Map && result['body'] != null) {
        try {
          final bodyStr = result['body'].toString();
          developer.log('📥 [4.dart] VLM 응답 수신: $bodyStr', name: 'VLM');

          final jsonResponse = json.decode(bodyStr);
          developer.log('✅ [4.dart] JSON 파싱 성공: $jsonResponse', name: 'VLM');

          // description 추출 시도 (두 가지 형태 지원)
          String? description;

          // 형태 1: {"description": "..."}
          if (jsonResponse is Map && jsonResponse['description'] != null) {
            description = jsonResponse['description'].toString();
            developer.log(
              '📝 [4.dart] description 추출 (직접): $description',
              name: 'VLM',
            );
          }
          // 형태 2: {"result": {"description": "..."}}
          else if (jsonResponse is Map && jsonResponse['result'] != null) {
            final result = jsonResponse['result'];
            if (result is Map && result['description'] != null) {
              description = result['description'].toString();
              developer.log(
                '📝 [4.dart] description 추출 (result 내부): $description',
                name: 'VLM',
              );
            }
          }

          if (description != null && description.isNotEmpty) {
            developer.log('🔊 [4.dart] TTS 호출 시작: "$description"', name: 'VLM');
            // TTS 초기화 보장
            await _ttsService.initialize();
            // TTS는 비동기로 시작 (카메라 종료를 기다리지 않음)
            _ttsService.speak(description).catchError((e) {
              developer.log('❌ [4.dart] TTS 호출 실패: $e', name: 'VLM');
            });
            developer.log('✅ [4.dart] TTS 호출 완료', name: 'VLM');
          } else {
            developer.log(
              '⚠️ [4.dart] description을 찾을 수 없음. JSON 구조: $jsonResponse',
              name: 'VLM',
            );
          }
        } catch (e) {
          // JSON 파싱 실패 시 무시 (기존 동작 유지)
          developer.log('❌ [4.dart] VLM 응답 파싱 실패: $e', name: 'VLM');
        }
      } else {
        developer.log('⚠️ [4.dart] 응답 body가 없음', name: 'VLM');
      }

      // TTS 시작 후 카메라 종료 (await하여 완료 보장)
      try {
        await _channel.invokeMethod('stopCamera');
        developer.log('✅ [4.dart] 카메라 종료 완료', name: 'VLM');
        print('✅ [4.dart] 카메라 종료 완료');
      } catch (e) {
        developer.log('❌ [4.dart] 카메라 종료 실패: $e', name: 'VLM');
        print('❌ [4.dart] 카메라 종료 실패: $e');
      }

      // 카메라 종료 후 Porcupine이 계속 실행되도록 보장
      // 약간의 지연을 두어 오디오 리소스가 완전히 해제되도록 함
      await Future.delayed(const Duration(milliseconds: 500));

      try {
        print('🔄 [4.dart] Porcupine 재시작 시작');
        developer.log('🔄 [4.dart] Porcupine 재시작 시작', name: 'Porcupine');
        await _porcupineService.ensureRunning();
        print('✅ [4.dart] Porcupine 재시작 완료');
        developer.log('✅ [4.dart] Porcupine 재시작 완료', name: 'Porcupine');
      } catch (e, stackTrace) {
        print('❌ [4.dart] Porcupine 재시작 실패: $e');
        developer.log(
          '❌ [4.dart] Porcupine 재시작 실패: $e',
          name: 'Porcupine',
          error: e,
          stackTrace: stackTrace,
        );
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('업로드 완료: ${result['body'] ?? 'Success'}')),
        );
      }
    } catch (e) {
      await _channel.invokeMethod('stopCamera').catchError((_) {});
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('업로드 실패: $e')));
      }
    }
  }

  // 현재 위치를 기준으로 지나간 점들을 체크 -> RouteTracker로 로직 이동
  void _checkAndUpdatePassedPoints(Position position) {
    final updated = _tracker.findClosestPointAndUpdate(
      position.latitude,
      position.longitude,
      Geolocator.distanceBetween,
    );
    if (updated) {
      setState(() {});
    }
  }

  void _checkDirectionAndVibrate() {
    double targetDir = _navService.routeBearing >= 0
        ? _navService.routeBearing
        : _navService.targetBearing;
    double currentDir = _navService.travelingBearing >= 0
        ? _navService.travelingBearing
        : _navService.deviceHeading;

    double diff = (targetDir - currentDir).abs();
    if (diff > 180) diff = 360 - diff;

    if (diff < 15 &&
        DateTime.now().difference(_lastVibrationTime).inSeconds >= 1) {
      HapticFeedback.vibrate();
      _lastVibrationTime = DateTime.now();
    }
  }

  // _normalizeAngle -> math_utils.normalizeAngle 로 이동됨

  // 방향 위젯 빌더
  Widget _buildDirectionWidget({
    required String label,
    required double angle,
    required String degrees,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        // 부드러운 회전을 위한 애니메이션
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: angle, end: angle),
          duration: const Duration(milliseconds: 100), // 부드러운 전환
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return Transform.rotate(
              angle: value,
              child: Icon(Icons.arrow_upward_rounded, size: 100, color: color),
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          "$degrees°",
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    double targetDirection = _navService.routeBearing >= 0
        ? _navService.routeBearing
        : _navService.targetBearing;
    // 센서 기반으로 통일 - GPS 오차 제거하여 안정적인 방향 표시
    double currentDirection = _navService.deviceHeading;

    // 라디안으로 변환
    double targetAngle = targetDirection * (math.pi / 180);
    double currentAngle = currentDirection * (math.pi / 180);

    // 360-0 wrap-around 처리 (짧은 경로로 회전)
    targetAngle = math_utils.normalizeAngle(targetAngle, _prevTargetAngle);
    currentAngle = math_utils.normalizeAngle(currentAngle, _prevCurrentAngle);

    // 다음 프레임을 위해 저장
    _prevTargetAngle = targetAngle;
    _prevCurrentAngle = currentAngle;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("실시간 길안내"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              ProgressIndicatorWidget(tracker: _tracker),
              // 상단 절반: 화살표 & 거리 정보 (Arrow Section)
              Expanded(
                flex: 1,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade800),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "남은 거리: ${_distanceToTarget.toStringAsFixed(0)}m",
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 30),

                      // 두 방향 동시 표시
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // 가야할 방향
                          _buildDirectionWidget(
                            label: "가야할 방향",
                            angle: targetAngle, // 이미 정규화된 라디안 값
                            degrees: targetDirection.toStringAsFixed(0),
                            color: Colors.yellowAccent,
                          ),
                          // 진행 방향
                          _buildDirectionWidget(
                            label: "진행 방향",
                            angle: currentAngle, // 이미 정규화된 라디안 값
                            degrees: currentDirection.toStringAsFixed(0),
                            color: Colors.greenAccent,
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),
                      Text(
                        _navService.travelingBearing >= 0
                            ? "(GPS 기반)"
                            : "(센서 기반)",
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ---------------------------------------------------------
              // 2. 하단 절반: 타임라인 형태 경로 안내
              // ---------------------------------------------------------
              Expanded(
                flex: 1,
                child: Container(
                  width: double.infinity,
                  color: Colors.black,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 리스트 헤더
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 15,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.grey.shade800),
                          ),
                          color: Colors.grey.shade900,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "상세 경로 안내",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            // 현재 구간 표시
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.yellowAccent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "${_tracker.currentSegmentIndex + 1}/${widget.routes.length}",
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 타임라인 위젯
                      Expanded(
                        child: RouteTimelineWidget(
                          routes: widget.routes,
                          currentSegmentIndex: _tracker.currentSegmentIndex,
                          currentStepIndex: _tracker.currentStepIndex,
                          onSegmentTap: (index) {
                            _tracker.moveToSegment(index);
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // 버스 도착 정보 오버레이
          if (_popupState.showPopup) _buildBusArrivalOverlay(),
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
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        color: Colors.black,
        child: SafeArea(
          child: ElevatedButton.icon(
            onPressed: () {
              _navService.stopLocationTracking(); // Screen5로 이동 전 GPS 추적 중지
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RouteTrackingMapScreen(
                    routes: widget.routes,
                    destinationName: widget.destinationName,
                  ),
                ),
              ).then((_) {
                // Screen5에서 돌아오면 콜백 재등록
                if (mounted) {
                  // 센서 재시작
                  _navService.ensureSensorRunning();

                  // 단계 변경 TTS 콜백 재등록
                  _tracker.onStepChanged =
                      (segmentIndex, stepIndex, description) {
                        if (mounted) {
                          _ttsService.speak(description);
                          setState(() {});
                        }
                      };

                  // 센서 방향 업데이트 콜백 재등록 (중요: 5.dart에서 덮어쓴거 복구)
                  _navService.onBearingUpdate = () {
                    if (mounted) {
                      setState(() {});
                    }
                  };

                  // GPS 추적 재개
                  _navService.startLocationTracking(
                    onUpdate: _onPositionUpdate,
                  );
                }
              });
            },
            icon: const Icon(Icons.map),
            label: const Text("경로 추적 지도 보기"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
