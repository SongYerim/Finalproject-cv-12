import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/spatial_audio_service.dart';

/// 공간음향 테스트 화면
///
/// 에뮬레이터에서 공간음향 기능을 테스트할 수 있는 화면입니다.
/// 슬라이더로 각도 차이를 조절하여 좌/우 스테레오 패닝을 확인할 수 있습니다.
class SpatialAudioTestScreen extends StatefulWidget {
  const SpatialAudioTestScreen({super.key});

  @override
  State<SpatialAudioTestScreen> createState() => _SpatialAudioTestScreenState();
}

class _SpatialAudioTestScreenState extends State<SpatialAudioTestScreen> {
  final SpatialAudioService _audioService = SpatialAudioService.instance;

  double _angleDiff = 0.0; // -180 ~ 180도
  double? _distance; // 거리 (미터), null이면 거리 무시
  bool _useDistance = false; // 거리 사용 여부
  bool _isPlaying = false;
  bool _isInitialized = false;

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

  Future<void> _togglePlayback() async {
    if (!_isInitialized) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('오디오 초기화 실패')));
      return;
    }

    if (_isPlaying) {
      await _audioService.stop();
    } else {
      await _audioService.start();
    }

    if (mounted) {
      setState(() {
        _isPlaying = _audioService.isPlaying;
      });
    }
  }

  void _updateAngle(double value) {
    setState(() {
      _angleDiff = value;
    });
    _audioService.updateDirection(_angleDiff, _useDistance ? _distance : null);
  }

  void _updateDistance(double? value) {
    setState(() {
      _distance = value;
    });
    _audioService.updateDirection(_angleDiff, _useDistance ? _distance : null);
  }

  String _getDirectionText() {
    if (_angleDiff.abs() < 15) {
      return '정면';
    } else if (_angleDiff < -15) {
      return '왼쪽 ${_angleDiff.abs().toStringAsFixed(0)}°';
    } else {
      return '오른쪽 ${_angleDiff.toStringAsFixed(0)}°';
    }
  }

  Color _getDirectionColor() {
    if (_angleDiff.abs() < 15) {
      return Colors.green;
    } else if (_angleDiff < 0) {
      return Colors.blue;
    } else {
      return Colors.orange;
    }
  }

  double _getPanValue() {
    return (_angleDiff / 90.0).clamp(-1.0, 1.0);
  }

  @override
  void dispose() {
    _audioService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('공간음향 테스트'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 상태 표시
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isInitialized ? Colors.green : Colors.red,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isInitialized ? Icons.check_circle : Icons.error,
                          color: _isInitialized ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isInitialized ? '초기화 완료' : '초기화 실패',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isPlaying ? '재생 중' : '정지',
                      style: TextStyle(
                        color: _isPlaying ? Colors.green : Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // 방향 시각화
              Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 방향 표시선
                    CustomPaint(
                      size: const Size(300, 300),
                      painter: DirectionPainter(
                        angle: _angleDiff,
                        color: _getDirectionColor(),
                      ),
                    ),
                    // 중앙 표시
                    Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    // 방향 텍스트
                    Positioned(
                      top: 20,
                      child: Text(
                        'N',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // 방향 정보
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      _getDirectionText(),
                      style: TextStyle(
                        color: _getDirectionColor(),
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildInfoItem(
                          '각도 차이',
                          '${_angleDiff.toStringAsFixed(1)}°',
                        ),
                        _buildInfoItem(
                          '패닝 값',
                          _getPanValue().toStringAsFixed(2),
                        ),
                        if (_useDistance && _distance != null)
                          _buildInfoItem(
                            '거리',
                            '${_distance!.toStringAsFixed(1)}m',
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // 슬라이더
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '각도 조절 (-180° ~ +180°)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Slider(
                    value: _angleDiff,
                    min: -180,
                    max: 180,
                    divisions: 360,
                    label: '${_angleDiff.toStringAsFixed(0)}°',
                    activeColor: _getDirectionColor(),
                    inactiveColor: Colors.grey[700],
                    onChanged: _updateAngle,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('-180°', style: TextStyle(color: Colors.grey)),
                      const Text('0°', style: TextStyle(color: Colors.grey)),
                      const Text('+180°', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 30),

              // 거리 조절 (체크박스 + 슬라이더)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: _useDistance,
                        onChanged: (value) {
                          setState(() {
                            _useDistance = value ?? false;
                            if (!_useDistance) {
                              _distance = null;
                            } else if (_distance == null) {
                              _distance = 50.0; // 기본값
                            }
                            _audioService.updateDirection(
                              _angleDiff,
                              _useDistance ? _distance : null,
                            );
                          });
                        },
                        activeColor: Colors.blue,
                      ),
                      const Text(
                        '거리 조절 사용',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (_useDistance) ...[
                    const SizedBox(height: 12),
                    Slider(
                      value: _distance ?? 50.0,
                      min: 1.0,
                      max: 100.0,
                      divisions: 99,
                      label: '${(_distance ?? 50.0).toStringAsFixed(1)}m',
                      activeColor: Colors.cyan,
                      inactiveColor: Colors.grey[700],
                      onChanged: (value) {
                        _updateDistance(value);
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('1m', style: TextStyle(color: Colors.grey)),
                        const Text('50m', style: TextStyle(color: Colors.grey)),
                        const Text(
                          '100m',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 40),

              // 재생/중지 버튼
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: _isInitialized ? _togglePlayback : null,
                  icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                  label: Text(_isPlaying ? '중지' : '재생'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isPlaying ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 안내 텍스트
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '💡 이어폰을 착용하고 슬라이더를 조절하면\n방향에 따라 소리가 이동하는 것을 확인할 수 있습니다.\n\n🎧 네이티브 HRTF + Virtualizer 사용\n⏱️ 정면에 가까울수록 비프 간격이 빨라집니다\n📏 거리 조절: 가까울수록 큰 소리, 멀수록 작은 소리',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// 방향 표시를 위한 CustomPainter
class DirectionPainter extends CustomPainter {
  final double angle;
  final Color color;

  DirectionPainter({required this.angle, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 30;

    // 각도를 라디안으로 변환 (0도가 위쪽이므로 -90도 회전)
    final radians = (angle - 90) * (3.14159 / 180);

    // 방향선 끝점 계산
    final endX = center.dx + radius * math.cos(radians);
    final endY = center.dy + radius * math.sin(radians);

    // 방향선 그리기
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(center, Offset(endX, endY), paint);

    // 화살표 그리기
    final arrowSize = 20.0;
    final arrowAngle = math.atan2(endY - center.dy, endX - center.dx);

    final arrow1 = Offset(
      endX - arrowSize * math.cos(arrowAngle - math.pi / 6),
      endY - arrowSize * math.sin(arrowAngle - math.pi / 6),
    );
    final arrow2 = Offset(
      endX - arrowSize * math.cos(arrowAngle + math.pi / 6),
      endY - arrowSize * math.sin(arrowAngle + math.pi / 6),
    );

    canvas.drawLine(Offset(endX, endY), arrow1, paint);
    canvas.drawLine(Offset(endX, endY), arrow2, paint);
  }

  @override
  bool shouldRepaint(DirectionPainter oldDelegate) {
    return oldDelegate.angle != angle || oldDelegate.color != color;
  }
}
