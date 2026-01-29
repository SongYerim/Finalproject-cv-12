import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/spatial_audio_service.dart';

/// 횡단보도 시뮬레이션 테스트 화면
///
/// 가상의 횡단보도에서 조이스틱으로 이동하면서
/// 공간음향이 어떻게 작동하는지 테스트할 수 있는 화면입니다.
class CrosswalkSimulationScreen extends StatefulWidget {
  const CrosswalkSimulationScreen({super.key});

  @override
  State<CrosswalkSimulationScreen> createState() =>
      _CrosswalkSimulationScreenState();
}

class _CrosswalkSimulationScreenState extends State<CrosswalkSimulationScreen> {
  final SpatialAudioService _audioService = SpatialAudioService.instance;

  // 플레이어 위치 (0.0 ~ 1.0 정규화)
  double _playerX = 0.5; // 가로 중앙
  double _playerY = 0.9; // 시작점 (아래쪽)

  // 플레이어 방향 (0 = 위쪽, 90 = 오른쪽, 180 = 아래, 270 = 왼쪽)
  double _playerDirection = 0.0;

  // 목표 지점 (횡단보도 끝)
  final double _exitX = 0.5;
  final double _exitY = 0.1;

  // 조이스틱 상태
  Offset _joystickPosition = Offset.zero;
  bool _isJoystickActive = false;

  // 이동 속도
  final double _moveSpeed = 0.005;

  bool _isInitialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initializeAudio();
  }

  Future<void> _initializeAudio() async {
    final success = await _audioService.initialize();
    if (mounted) {
      setState(() {
        _isInitialized = success;
      });
    }
  }

  void _startAudio() async {
    if (!_isInitialized) return;
    await _audioService.start();
    setState(() {
      _isPlaying = true;
    });
    _updateSpatialAudio();
  }

  void _stopAudio() async {
    await _audioService.stop();
    setState(() {
      _isPlaying = false;
    });
  }

  void _resetPosition() {
    setState(() {
      _playerX = 0.5;
      _playerY = 0.9;
      _playerDirection = 0.0;
    });
    _updateSpatialAudio();
  }

  /// 목표 지점까지의 거리 계산 (정규화된 단위)
  double _getDistanceToExit() {
    final dx = _exitX - _playerX;
    final dy = _exitY - _playerY;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// 목표 지점 방향 계산 (0-360도)
  double _getBearingToExit() {
    final dx = _exitX - _playerX;
    final dy = _exitY - _playerY;
    // atan2(dx, -dy)로 위쪽이 0도가 되도록
    double bearing = math.atan2(dx, -dy) * (180 / math.pi);
    if (bearing < 0) bearing += 360;
    return bearing;
  }

  /// 각도 차이 계산 (-180 ~ 180)
  double _getAngleDiff() {
    final bearing = _getBearingToExit();
    double diff = bearing - _playerDirection;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return diff;
  }

  /// 공간음향 업데이트
  void _updateSpatialAudio() {
    if (!_isPlaying) return;

    final angleDiff = _getAngleDiff();
    // 정규화된 거리를 미터로 변환 (횡단보도 길이 약 20m 가정)
    final distance = _getDistanceToExit() * 25.0;

    _audioService.updateDirection(angleDiff, distance);
  }

  /// 조이스틱 이동 처리
  void _onJoystickMove(Offset delta) {
    if (delta == Offset.zero) return;

    setState(() {
      // 조이스틱 방향으로 플레이어 방향 업데이트
      if (delta.distance > 0.1) {
        _playerDirection = math.atan2(delta.dx, -delta.dy) * (180 / math.pi);
        if (_playerDirection < 0) _playerDirection += 360;
      }

      // 플레이어 이동
      final moveX = delta.dx * _moveSpeed;
      final moveY = delta.dy * _moveSpeed;

      _playerX = (_playerX + moveX).clamp(0.1, 0.9);
      _playerY = (_playerY + moveY).clamp(0.05, 0.95);
    });

    _updateSpatialAudio();

    // 목표 지점 도착 확인
    if (_getDistanceToExit() < 0.05) {
      _showArrivalDialog();
    }
  }

  void _showArrivalDialog() {
    _stopAudio();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🎉 도착!'),
        content: const Text('횡단보도를 성공적으로 건넜습니다.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetPosition();
            },
            child: const Text('다시 시작'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _audioService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final crosswalkWidth = screenSize.width * 0.8;
    final crosswalkHeight = screenSize.height * 0.5;

    return Scaffold(
      appBar: AppBar(
        title: const Text('횡단보도 시뮬레이션'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey[900],
      body: SafeArea(
        child: Column(
          children: [
            // 상태 표시
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.black,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildInfoChip(
                    '거리',
                    '${(_getDistanceToExit() * 25).toStringAsFixed(1)}m',
                    Colors.blue,
                  ),
                  _buildInfoChip(
                    '각도',
                    '${_getAngleDiff().toStringAsFixed(0)}°',
                    _getAngleDiff().abs() < 30 ? Colors.green : Colors.orange,
                  ),
                  _buildInfoChip(
                    '방향',
                    '${_playerDirection.toStringAsFixed(0)}°',
                    Colors.purple,
                  ),
                ],
              ),
            ),

            // 횡단보도 영역
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.all(16),
                child: CustomPaint(
                  size: Size(crosswalkWidth, crosswalkHeight),
                  painter: CrosswalkPainter(
                    playerX: _playerX,
                    playerY: _playerY,
                    playerDirection: _playerDirection,
                    exitX: _exitX,
                    exitY: _exitY,
                  ),
                  child: Container(),
                ),
              ),
            ),

            // 조이스틱 및 컨트롤
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // 조이스틱
                    Expanded(flex: 2, child: Center(child: _buildJoystick())),

                    // 컨트롤 버튼
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 재생/중지 버튼
                          SizedBox(
                            width: 80,
                            height: 80,
                            child: ElevatedButton(
                              onPressed: _isInitialized
                                  ? (_isPlaying ? _stopAudio : _startAudio)
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isPlaying
                                    ? Colors.red
                                    : Colors.green,
                                shape: const CircleBorder(),
                              ),
                              child: Icon(
                                _isPlaying ? Icons.stop : Icons.play_arrow,
                                size: 40,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // 리셋 버튼
                          ElevatedButton.icon(
                            onPressed: _resetPosition,
                            icon: const Icon(Icons.refresh),
                            label: const Text('리셋'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 안내 텍스트
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.black,
              child: const Text(
                '💡 조이스틱으로 이동하세요. 소리가 나는 방향이 출구입니다.\n정면에 가까울수록 빠른 비프음이 들립니다.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 10)),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJoystick() {
    const double size = 150;
    const double knobSize = 60;

    return GestureDetector(
      onPanStart: (details) {
        setState(() {
          _isJoystickActive = true;
        });
      },
      onPanUpdate: (details) {
        final center = Offset(size / 2, size / 2);
        final localPosition = details.localPosition;
        var delta = localPosition - center;

        // 최대 범위 제한
        final maxRadius = (size - knobSize) / 2;
        if (delta.distance > maxRadius) {
          delta = Offset.fromDirection(delta.direction, maxRadius);
        }

        setState(() {
          _joystickPosition = delta / maxRadius; // -1 ~ 1 정규화
        });

        _onJoystickMove(_joystickPosition);
      },
      onPanEnd: (details) {
        setState(() {
          _isJoystickActive = false;
          _joystickPosition = Offset.zero;
        });
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey[600]!, width: 3),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 십자 가이드
            CustomPaint(
              size: const Size(size, size),
              painter: JoystickGuidePainter(),
            ),
            // 조이스틱 손잡이
            Transform.translate(
              offset: _joystickPosition * ((size - knobSize) / 2),
              child: Container(
                width: knobSize,
                height: knobSize,
                decoration: BoxDecoration(
                  color: _isJoystickActive ? Colors.green : Colors.grey[600],
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(2, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.control_camera,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 횡단보도 그리기
class CrosswalkPainter extends CustomPainter {
  final double playerX;
  final double playerY;
  final double playerDirection;
  final double exitX;
  final double exitY;

  CrosswalkPainter({
    required this.playerX,
    required this.playerY,
    required this.playerDirection,
    required this.exitX,
    required this.exitY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // 도로 배경 (회색)
    paint.color = Colors.grey[700]!;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // 횡단보도 영역 (흰색 줄무늬)
    final crosswalkLeft = size.width * 0.2;
    final crosswalkRight = size.width * 0.8;
    final crosswalkTop = size.height * 0.05;
    final crosswalkBottom = size.height * 0.95;
    final stripeCount = 10;
    final stripeHeight = (crosswalkBottom - crosswalkTop) / (stripeCount * 2);

    paint.color = Colors.white;
    for (int i = 0; i < stripeCount; i++) {
      final top = crosswalkTop + i * stripeHeight * 2;
      canvas.drawRect(
        Rect.fromLTRB(crosswalkLeft, top, crosswalkRight, top + stripeHeight),
        paint,
      );
    }

    // 횡단보도 테두리
    paint.color = Colors.yellow;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 4;
    canvas.drawRect(
      Rect.fromLTRB(
        crosswalkLeft,
        crosswalkTop,
        crosswalkRight,
        crosswalkBottom,
      ),
      paint,
    );

    // 목표 지점 (출구)
    final exitPosX = exitX * size.width;
    final exitPosY = exitY * size.height;
    paint.color = Colors.green;
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(Offset(exitPosX, exitPosY), 20, paint);

    // 출구 아이콘
    final textPainter = TextPainter(
      text: const TextSpan(text: '🏁', style: TextStyle(fontSize: 24)),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        exitPosX - textPainter.width / 2,
        exitPosY - textPainter.height / 2,
      ),
    );

    // 플레이어
    final playerPosX = playerX * size.width;
    final playerPosY = playerY * size.height;

    // 플레이어 몸체
    paint.color = Colors.blue;
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(Offset(playerPosX, playerPosY), 15, paint);

    // 플레이어 방향 표시 (삼각형)
    paint.color = Colors.red;
    final directionRad = playerDirection * (math.pi / 180);
    final arrowLength = 25.0;
    final arrowX = playerPosX + math.sin(directionRad) * arrowLength;
    final arrowY = playerPosY - math.cos(directionRad) * arrowLength;

    final path = Path();
    path.moveTo(arrowX, arrowY);
    path.lineTo(
      playerPosX + math.sin(directionRad + 2.5) * 12,
      playerPosY - math.cos(directionRad + 2.5) * 12,
    );
    path.lineTo(
      playerPosX + math.sin(directionRad - 2.5) * 12,
      playerPosY - math.cos(directionRad - 2.5) * 12,
    );
    path.close();
    canvas.drawPath(path, paint);

    // 시작 지점 레이블
    final startTextPainter = TextPainter(
      text: const TextSpan(
        text: '시작',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    startTextPainter.layout();
    startTextPainter.paint(
      canvas,
      Offset(size.width / 2 - startTextPainter.width / 2, size.height - 25),
    );

    // 출구 레이블
    final exitTextPainter = TextPainter(
      text: const TextSpan(
        text: '출구',
        style: TextStyle(
          color: Colors.green,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    exitTextPainter.layout();
    exitTextPainter.paint(
      canvas,
      Offset(exitPosX - exitTextPainter.width / 2, exitPosY - 40),
    );
  }

  @override
  bool shouldRepaint(CrosswalkPainter oldDelegate) {
    return oldDelegate.playerX != playerX ||
        oldDelegate.playerY != playerY ||
        oldDelegate.playerDirection != playerDirection;
  }
}

/// 조이스틱 가이드 그리기
class JoystickGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[600]!.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // 십자선
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      paint,
    );

    // 원
    canvas.drawCircle(center, radius * 0.5, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
