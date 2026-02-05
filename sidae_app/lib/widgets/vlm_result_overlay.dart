import 'dart:typed_data';
import 'package:flutter/material.dart';

class VlmResultOverlay extends StatelessWidget {
  final Uint8List? imageBytes;
  final String response;
  final int? responseTimeMs;
  final VoidCallback? onClose;

  const VlmResultOverlay({
    super.key,
    required this.imageBytes,
    required this.response,
    this.responseTimeMs,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    if (imageBytes == null) return const SizedBox.shrink();

    return AspectRatio(
      aspectRatio: 3 / 4, // 카메라 비율 (일반적인 세로 모드)
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFD400), width: 2),
        ),
        padding: const EdgeInsets.all(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(imageBytes!, fit: BoxFit.cover),
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
                      response.isNotEmpty ? response : 'No response',
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
              if (responseTimeMs != null)
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
                      '응답 시간: ${responseTimeMs}ms',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              // 닫기 버튼 (좌상단 - 옵션)
              if (onClose != null)
                Positioned(
                  top: 8,
                  left: 8,
                  child: GestureDetector(
                    onTap: onClose,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
