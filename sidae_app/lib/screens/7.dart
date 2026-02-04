import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
// import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import '../services/bus_arrival_service.dart';
import '../services/bus_detector_service.dart';
import '../services/tts_service.dart';
import '../services/route_tracker.dart';
import '../utils/bus_utils.dart' as bus_utils;
import '8.dart';

class BusArrivalScreen extends StatefulWidget {
  final String busNumber;
  final String stationName;
  final bool enableCamera; // 카메라 모드 활성화 파라미터
  /// 버스 하차 지점 좌표 (하차 알림용)
  final double? exitLat;
  final double? exitLng;

  const BusArrivalScreen({
    super.key,
    required this.busNumber,
    required this.stationName,
    this.enableCamera = false,
    this.exitLat,
    this.exitLng,
  });

  @override
  State<BusArrivalScreen> createState() => _BusArrivalScreenState();
}

class _BusArrivalScreenState extends State<BusArrivalScreen> {
  final BusArrivalService _arrivalService = BusArrivalService();
  final TtsService _ttsService = TtsService.instance;
  final BusDetectorService _busDetectorService = BusDetectorService();

  BusArrival? _arrival;
  bool _isLoading = true;

  // 카메라 상태
  bool _isBusApproaching = false;
  bool _cameraActive = false;
  String _detectionStatus = '';

  Uint8List? _croppedBusImage;

  // 매칭 상태
  String _matchStatus = ''; // 'MATCH', 'MISMATCH', 'CHECKING', ''
  String _lastOcrResult = '';
  int? _lastResponseTimeMs; // VLM 응답 시간
  Timer? _mismatchTimer; // MISMATCH 상태 유지 타이머

  // 태그 인식 상태
  int _tagRecognitionCount = 0;
  bool _isRecognizingTag = false;
  String _tagStatus = '';
  Uint8List? _tagCapturedImage; // 태그 인식용 캐처 이미지
  String? _tagResponse; // 태그 인식 서버 응답

  @override
  void initState() {
    super.initState();
    _initializeService();

    // enableCamera가 true면 바로 카메라 시작
    if (widget.enableCamera) {
      _isBusApproaching = true;
      _startCamera();
    }
  }

  Future<void> _initializeService() async {
    await _ttsService.initialize();
    await _ttsService.speak("버스 정류장에 도착했습니다. 도착 정보를 확인합니다.");

    _arrivalService.onArrivalUpdate = (arrival) {
      if (!mounted) return;
      setState(() {
        _arrival = arrival;
        _isLoading = false;
      });

      // TTS로 도착 정보 안내
      if (arrival != null) {
        _ttsService.speak("${arrival.busNumber}번 버스, ${arrival.statusMsg}");

        // "곧 도착" 상태 감지 → 카메라 활성화
        if (bus_utils.isBusApproachingStatus(arrival.statusMsg) &&
            !_cameraActive) {
          _isBusApproaching = true;
          _startCamera();
        }
      }
    };

    await _arrivalService.startTracking(widget.busNumber, widget.stationName);
  }

  // bus_utils.isBusApproachingStatus -> bus_utils.isBusApproachingStatus 로 이동됨

  /// 카메라 시작
  Future<void> _startCamera() async {
    if (_cameraActive) return;

    setState(() {
      _detectionStatus = '카메라 시작 중...';
      _matchStatus = '';
    });

    _busDetectorService.onStatusChanged = (status) {
      if (mounted) {
        setState(() {
          _detectionStatus = status;
        });
      }
    };

    _busDetectorService.onBusCropped = (croppedImage) {
      if (mounted) {
        setState(() {
          _croppedBusImage = croppedImage;
          // MATCH나 MISMATCH 상태가 아닐 때만 CHECKING으로 변경
          if (_matchStatus != 'MATCH' && _matchStatus != 'MISMATCH') {
            _matchStatus = 'CHECKING';
          }
        });
        // TODO: OCR 서버로 전송 (Service 내부에서 처리됨)
      }
    };

    // OCR 결과 수신
    _busDetectorService.onBusNumberFound = (ocrResult, responseTimeMs) {
      // developer.log(
      //   '🎯 [7.dart] OCR 콜백 수신: $ocrResult (응답시간: ${responseTimeMs}ms)',
      //   name: 'BusArrivalScreen',
      // );
      if (mounted) {
        // developer.log(
        //   '  - mounted: true, _checkMatch 호출',
        //   name: 'BusArrivalScreen',
        // );
        setState(() {
          _lastResponseTimeMs = responseTimeMs;
        });
        _checkMatch(ocrResult);
      } else {
        // developer.log('  - mounted: false, 스킵', name: 'BusArrivalScreen');
      }
    };

    final success = await _busDetectorService.startDetection();
    if (mounted) {
      setState(() {
        _cameraActive = success;
        if (!success) {
          _detectionStatus = '카메라 시작 실패';
        }
      });
    }
  }

  // 매칭 로직
  void _checkMatch(String ocrResult) {
    // developer.log('🔍 [7.dart] _checkMatch 시작', name: 'BusArrivalScreen');
    // developer.log('  - ocrResult: $ocrResult', name: 'BusArrivalScreen');
    // developer.log(
    //   '  - widget.busNumber: ${widget.busNumber}',
    //   name: 'BusArrivalScreen',
    // );

    _lastOcrResult = ocrResult;

    // 1. 버스 번호 매칭 (문자열 포함 여부)
    bool isNumberMatch = ocrResult.contains(widget.busNumber);
    // developer.log(
    //   '  - isNumberMatch: $isNumberMatch',
    //   name: 'BusArrivalScreen',
    // );

    // 2. 번호판 매칭 (뒤 4자리)
    bool isPlateMatch = false;
    if (_arrival != null && _arrival!.plateNo.isNotEmpty) {
      String plate = _arrival!.plateNo;
      // 뒤 4자리 추출
      String last4 = plate.length >= 4
          ? plate.substring(plate.length - 4)
          : plate;
      isPlateMatch = ocrResult.contains(last4);
      // developer.log(
      //   '  - plateNo: $plate, last4: $last4, isPlateMatch: $isPlateMatch',
      //   name: 'BusArrivalScreen',
      // );
    }

    if (isNumberMatch || isPlateMatch) {
      // developer.log('✅ [7.dart] 매칭 성공!', name: 'BusArrivalScreen');

      // 중복 실행 방지
      if (_matchStatus != 'MATCH') {
        setState(() {
          _matchStatus = 'MATCH';
        });
        _ttsService.speak("탑승할 버스입니다! ${widget.busNumber}번");

        // 버스 탑승 상태 설정 (도보 경로 감지 비활성화)
        RouteTracker.instance.setOnBus(true);

        // 매칭 성공 시 추론 중지 (배터리 절약)
        _busDetectorService.stopInference();

        // 태그 인식 시작
        _startTagRecognition();
      }
    } else {
      // developer.log('❌ [7.dart] 매칭 실패', name: 'BusArrivalScreen');
      if (_matchStatus != 'MATCH') {
        setState(() {
          _matchStatus = 'MISMATCH';
        });

        // 5초 후 MISMATCH 상태 해제 (새로운 감지 허용)
        _mismatchTimer?.cancel();
        _mismatchTimer = Timer(const Duration(seconds: 5), () {
          if (mounted && _matchStatus == 'MISMATCH') {
            setState(() {
              _matchStatus = '';
            });
          }
        });
        // _ttsService.speak("다른 버스입니다.");
      }
    }
  }

  /// 태그 인식 시작
  Future<void> _startTagRecognition() async {
    setState(() {
      _isRecognizingTag = true;
      _tagRecognitionCount = 0;
    });

    // 버스 탑승을 위해 5초 대기
    // developer.log('⏰ [태그 인식] 5초 후 시작...', name: 'BusArrivalScreen');
    _ttsService.speak('5초 후 태그 인식을 시작합니다');
    await Future.delayed(const Duration(seconds: 5));

    // developer.log('🏷️ [태그 인식] 시작', name: 'BusArrivalScreen');
    _ttsService.speak('태그 인식 시작');
    await _recognizeTagSequentially();
  }

  /// 태그 인식 순차 실행
  Future<void> _recognizeTagSequentially() async {
    if (_tagRecognitionCount >= 3) {
      // 3번 완료 → 8.dart로 이동
      // developer.log('🏷️ [태그 인식] 3번 완료 - 8.dart로 이동', name: 'BusArrivalScreen');
      _navigateToBusOnlyScreen();
      return;
    }

    _tagRecognitionCount++;
    setState(() {
      _tagStatus = '태그 인식 중... ($_tagRecognitionCount/3)';
    });
    // developer.log(
    //   '🏷️ [태그 인식] 시도 $_tagRecognitionCount/3 시작',
    //   name: 'BusArrivalScreen',
    // );

    // API 서버로 전송 (mode: tag_)
    final result = await _busDetectorService.sendTagRecognition();

    if (result != null) {
      // developer.log(
      //   '📦 [태그 인식] 서버 응답 수신: ${result.response}',
      //   name: 'BusArrivalScreen',
      // );

      String displayText = '';
      String ttsText = '';

      // JSON 파싱하여 result 추출
      try {
        final jsonResponse = json.decode(result.response);
        // developer.log(
        //   '🔍 [태그 인식] 파싱된 JSON: $jsonResponse',
        //   name: 'BusArrivalScreen',
        // );

        // tag_ 모드 응답 처리 ("des" 필드 확인)
        if (jsonResponse.containsKey('des')) {
          displayText = jsonResponse['des'];
          ttsText = displayText;

          if (displayText == '대상을 찾을 수 없습니다.') {
            // 실패로 처리하고 싶다면 여기 로직 추가 가능하지만,
            // 현재 구조상 displayText가 있으면 성공 로그를 찍으므로
            // 실패로 간주하려면 result.success를 false로 하거나 별도 처리가 필요함.
            // 하지만 서버 응답이 200 OK면 result.success는 true임.
            // 따라서 내용만 표시.
          }
        }
        // 기존 result 필드 처리 (다른 모드 호환)
        else {
          final resultData = jsonResponse['result'];

          if (resultData != null) {
            // found 필드 확인
            final found = resultData['found'];
            if (found == false || resultData['error'] != null) {
              displayText = '승차태그를 찾을 수 없습니다';
              ttsText = '승차태그를 찾을 수 없습니다';
            } else {
              // result 데이터를 문자열로 변환
              final resultStr = resultData.toString();
              displayText = resultStr;

              // TTS용으로 간결하게 변환
              if (resultData is Map) {
                final parts = <String>[];
                resultData.forEach((key, value) {
                  if (key != 'found' && key != 'error') {
                    parts.add('$key: $value');
                  }
                });
                ttsText = parts.join(', ');
              } else {
                ttsText = resultStr;
              }
            }
          } else {
            displayText = result.response;
            ttsText = '태그 인식 실패 (데이터 없음)';
          }
        }
      } catch (e) {
        // JSON 파싱 실패 시 원본 표시
        // developer.log('JSON 파싱 실패: $e', name: 'BusArrivalScreen');
        displayText = result.response;
        ttsText = '태그 인식 실패';
      }

      setState(() {
        _tagCapturedImage = result.imageBytes;
        _tagResponse = displayText;
      });

      if (result.success) {
        // developer.log(
        //   '✅ [태그 인식] $_tagRecognitionCount/3 성공: $displayText',
        //   name: 'BusArrivalScreen',
        // );
        // TTS로 응답 읽어주기
        _ttsService.speak('태그 $_tagRecognitionCount번: $ttsText');
      } else {
        // developer.log(
        //   '⚠️ [태그 인식] $_tagRecognitionCount/3 실패: $displayText',
        //   name: 'BusArrivalScreen',
        // );
        _ttsService.speak('태그 인식 실패');
      }
    } else {
      // developer.log(
      //   '⚠️ [태그 인식] $_tagRecognitionCount/3 실패 (계속 진행)',
      //   name: 'BusArrivalScreen',
      // );
      _ttsService.speak('태그 인식 실패');
    }

    // 다음 시도까지 1초 대기 (디버깅 용이성)
    // developer.log('⏰ [태그 인식] 1초 대기 후 다음 시도...', name: 'BusArrivalScreen');
    await Future.delayed(const Duration(seconds: 1));

    // 서버 응답 받은 후 다음 전송
    await _recognizeTagSequentially();
  }

  /// 8.dart(BusOnlyScreen)로 이동
  void _navigateToBusOnlyScreen() {
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => BusOnlyScreen(
          returnMidLat: widget.exitLat,
          returnMidLng: widget.exitLng,
          returnDistanceMeters: 30.0, // 30m 반경으로 하차 감지
        ),
      ),
    );
  }

  /// 카메라 중지
  void _stopCamera() {
    _busDetectorService.stopDetection();
    setState(() {
      _cameraActive = false;

      _croppedBusImage = null;
      _matchStatus = '';
    });
  }

  Future<void> _onRefresh() async {
    setState(() => _isLoading = true);
    await _arrivalService.refresh();
  }

  @override
  void dispose() {
    // developer.log(
    //   '🗑️ [BusArrivalScreen] dispose() 시작',
    //   name: 'BusArrivalScreen',
    // );

    // 카메라가 활성화된 경우 명시적으로 중지
    if (_cameraActive) {
      // developer.log('  - 카메라 활성화 상태, 명시적 중지', name: 'BusArrivalScreen');
      _busDetectorService.stopDetection();
      _cameraActive = false;
    }

    // 콜백 제거
    // developer.log('  - 콜백 제거', name: 'BusArrivalScreen');
    _busDetectorService.onStatusChanged = null;
    _busDetectorService.onBusDetected = null;
    _busDetectorService.onBusCropped = null;
    _busDetectorService.onBusNumberFound = null;
    _arrivalService.onArrivalUpdate = null;

    // 타이머 정리
    _mismatchTimer?.cancel();
    _mismatchTimer = null;

    // 서비스 정리
    // developer.log('  - 서비스 정리', name: 'BusArrivalScreen');
    _arrivalService.dispose();
    _busDetectorService.dispose();

    // developer.log(
    //   '✅ [BusArrivalScreen] dispose() 완료',
    //   name: 'BusArrivalScreen',
    // );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // 카메라 토글 버튼
          IconButton(
            icon: Icon(
              _cameraActive ? Icons.videocam : Icons.videocam_off,
              color: _cameraActive ? Colors.green : Colors.grey,
            ),
            onPressed: () {
              if (_cameraActive) {
                _stopCamera();
              } else {
                _startCamera();
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. 전체 화면 카메라 프리뷰 (배경)
          _buildFullCameraPreview(),

          // 2. 바운딩 박스 오버레이 (네이티브에서 처리하므로 Flutter 페인터 제거)
          // if (_currentDetection != null) _buildBoundingBoxOverlay(),

          // 매칭 결과 오버레이 (성공 시 화면 테두리 등 효과)
          if (_matchStatus == 'MATCH')
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 8),
                ),
              ),
            ),

          // 3. 하단 정보 패널
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomInfoPanel(),
          ),

          // 4. Crop 이미지 프리뷰 (우측 하단)
          if (_croppedBusImage != null)
            Positioned(
              right: 16,
              bottom: 140,
              child: _buildCroppedImagePreview(),
            ),

          // 5. 타야할 버스 정보 표시 (좌측 상단)
          Positioned(top: 100, left: 16, child: _buildTargetBusInfo()),

          // 7. 매칭 결과 텍스트 (중앙 상단)
          if (_matchStatus == 'MATCH')
            Positioned(
              top: 150,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  color: Colors.green,
                  child: const Text(
                    "탑승할 버스입니다!",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            )
          else if (_matchStatus == 'MISMATCH')
            Positioned(
              top: 150,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  color: Colors.red.withOpacity(0.8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "다른 버스입니다 ($_lastOcrResult)",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      if (_lastResponseTimeMs != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          "응답 시간: ${_lastResponseTimeMs}ms",
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

          // 태그 인식 결과 표시
          if (_isRecognizingTag && _tagCapturedImage != null)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: Container(
                height: 250,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFFD400), width: 2),
                ),
                child: Column(
                  children: [
                    // 헤더
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFD400),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(14),
                          topRight: Radius.circular(14),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.credit_card, color: Colors.black),
                          const SizedBox(width: 8),
                          Text(
                            _tagStatus,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 이미지와 응답
                    Expanded(
                      child: Row(
                        children: [
                          // 캡처된 이미지
                          Expanded(
                            flex: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  _tagCapturedImage!,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          // 서버 응답
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Center(
                                child: Text(
                                  _tagResponse ?? '응답 대기 중...',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
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

  /// 전체 화면 카메라 프리뷰
  Widget _buildFullCameraPreview() {
    if (!_cameraActive || !_busDetectorService.isActive) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.green),
              const SizedBox(height: 16),
              Text(
                _detectionStatus.isEmpty ? '카메라 준비 중...' : _detectionStatus,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // 네이티브 AndroidView 사용 (6.dart 참조)
    return const SizedBox.expand(child: AndroidView(viewType: 'cameraPreview'));
  }

  /// 하단 정보 패널
  Widget _buildBottomInfoPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.9)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 정류장 + 버스 정보
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.stationName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 새로고침 버튼 + 카운트다운
                StreamBuilder<int>(
                  stream: _arrivalService.countdownStream,
                  initialData: 30,
                  builder: (context, snapshot) {
                    final remaining = snapshot.data ?? 30;
                    return TextButton.icon(
                      onPressed: _onRefresh,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      icon: const Icon(
                        Icons.refresh,
                        color: Colors.white,
                        size: 16,
                      ),
                      label: Text(
                        '${remaining}초',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 버스 번호 + 상태
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.busNumber,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (_arrival != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _arrival!.statusMsg,
                          style: TextStyle(
                            color:
                                bus_utils.isBusApproachingStatus(
                                  _arrival!.statusMsg,
                                )
                                ? Colors.orange
                                : Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        // 차량 번호 (있는 경우에만 표시)
                        if (_arrival!.plateNo.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              _arrival!.plateNo,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                else if (_isLoading)
                  const Text(
                    '도착 정보 확인 중...',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Crop 이미지 프리뷰
  Widget _buildCroppedImagePreview() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 이미지
            Image.memory(
              _croppedBusImage!,
              width: 120,
              height: 80,
              fit: BoxFit.cover,
            ),

            // 라벨
          ],
        ),
      ),
    );
  }

  /// 타야할 버스 정보 표시
  Widget _buildTargetBusInfo() {
    // 차량 번호 뒤 4자리 추출
    String? plateDisplay;
    if (_arrival != null && _arrival!.plateNo.isNotEmpty) {
      String plate = _arrival!.plateNo;
      plateDisplay = plate.length >= 4
          ? plate.substring(plate.length - 4)
          : plate;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 제목
          const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white, size: 16),
              SizedBox(width: 6),
              Text(
                '타야할 버스',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 버스 번호
          Row(
            children: [
              const Text(
                '번호: ',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              Text(
                widget.busNumber,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          // 차량 번호 (있는 경우만)
          if (plateDisplay != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Text(
                  '차량: ',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                Text(
                  plateDisplay,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
          // OCR 결과 표시 (있는 경우만)
          if (_lastOcrResult.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(color: Colors.white38, height: 1),
            const SizedBox(height: 8),
            const Text(
              'OCR 결과:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              _lastOcrResult,
              style: TextStyle(
                color: _matchStatus == 'MATCH'
                    ? Colors.greenAccent
                    : Colors.orange,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
