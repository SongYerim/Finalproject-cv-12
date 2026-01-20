import 'package:flutter/material.dart';
import '../services/route_tracker.dart';

/// 진행 상황 표시 위젯 (4.dart와 5.dart에서 공통 사용)
class ProgressIndicatorWidget extends StatelessWidget {
  final RouteTracker tracker;

  const ProgressIndicatorWidget({
    super.key,
    required this.tracker,
  });

  @override
  Widget build(BuildContext context) {
    int passedCount = tracker.pointsPassed.where((passed) => passed).length;
    double progress = tracker.getProgress();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: Colors.grey.shade900,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "진행 상황",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "$passedCount / ${tracker.allPathPoints.length} 지점 통과",
                style: const TextStyle(
                  color: Colors.yellowAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.grey.shade700,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
            ),
          ),
        ],
      ),
    );
  }
}
