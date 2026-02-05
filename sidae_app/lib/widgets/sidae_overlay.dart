import 'package:flutter/material.dart';

/// STT 진행 중 오버레이 위젯
/// 시대야 버튼을 눌렀을 때 표시되는 음성인식 오버레이
class SidaeOverlay extends StatelessWidget {
  /// STT 진행 중 여부
  final bool isListening;

  /// STT 텍스트 (부분 결과 및 최종 결과)
  final String sttText;

  /// 주요 색상 (기본값: null이면 Theme에서 가져옴)
  final Color? primaryColor;

  const SidaeOverlay({
    super.key,
    required this.isListening,
    required this.sttText,
    this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    if (!isListening) {
      return const SizedBox.shrink();
    }

    final color = primaryColor ?? Theme.of(context).primaryColor;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
          border: Border(
            bottom: BorderSide(
              color: color,
              width: 2,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '시대에게 어떤 질문을 하고 싶으신가요?',
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (sttText.isNotEmpty)
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
                    Icon(
                      Icons.mic,
                      color: color,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          sttText,
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
                  Icon(
                    Icons.mic,
                    color: color,
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
    );
  }
}
