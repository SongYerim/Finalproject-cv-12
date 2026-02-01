import 'package:flutter/material.dart';
import '../models/route_model.dart';

/// 경로 타임라인 위젯 (4.dart, 5.dart 공용)
/// 도보/버스 구간을 시각적으로 분리하여 표시
class RouteTimelineWidget extends StatelessWidget {
  final List<RouteSegment> routes;
  final int currentSegmentIndex;
  final int currentStepIndex;
  final bool compact; // 컴팩트 모드 (5.dart용)
  final Function(int segmentIndex)? onSegmentTap;

  const RouteTimelineWidget({
    super.key,
    required this.routes,
    this.currentSegmentIndex = 0,
    this.currentStepIndex = 0,
    this.compact = false,
    this.onSegmentTap,
  });

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty) {
      return const Center(
        child: Text("경로 정보가 없습니다.", style: TextStyle(color: Colors.grey)),
      );
    }

    if (compact) {
      return _buildCompactTimeline();
    }

    return _buildFullTimeline();
  }

  /// 전체 타임라인 (4.dart용)
  Widget _buildFullTimeline() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 출발 지점
          _buildTimelinePoint("출발", isStart: true),

          // 각 구간 표시
          for (int i = 0; i < routes.length; i++) ...[
            _buildTimelineSegment(
              routes[i],
              segmentIndex: i,
              isCurrent: i == currentSegmentIndex,
              isPassed: i < currentSegmentIndex,
            ),
          ],

          // 도착 지점
          _buildTimelinePoint("도착", isEnd: true),
        ],
      ),
    );
  }

  /// 컴팩트 타임라인 (5.dart용 - 현재 구간만 강조)
  Widget _buildCompactTimeline() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(top: BorderSide(color: Colors.grey[800]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 현재 구간 표시
          if (currentSegmentIndex < routes.length)
            _buildCompactSegmentCard(routes[currentSegmentIndex]),

          const SizedBox(height: 8),

          // 진행 바
          _buildProgressBar(),
        ],
      ),
    );
  }

  Widget _buildCompactSegmentCard(RouteSegment segment) {
    final isWalk = segment.moveType == "WALK";
    final color = isWalk ? Colors.green : Colors.blue;
    final icon = isWalk ? Icons.directions_walk : Icons.directions_bus;
    final label = isWalk ? "도보" : "버스 ${segment.transportName ?? ''}";

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (!isWalk && segment.endStation != null)
                Text(
                  "→ ${segment.endStation} 하차",
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                ),
              if (isWalk &&
                  segment.stepDescription.isNotEmpty &&
                  currentStepIndex < segment.stepDescription.length)
                Text(
                  segment.stepDescription[currentStepIndex],
                  style: TextStyle(color: Colors.grey[300], fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        // 남은 정거장 표시 (버스)
        if (!isWalk && segment.stations.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "${segment.stations.length}정",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProgressBar() {
    return Row(
      children: [
        for (int i = 0; i < routes.length; i++) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => onSegmentTap?.call(i),
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: i < currentSegmentIndex
                      ? Colors.green
                      : (i == currentSegmentIndex
                            ? Colors.yellowAccent
                            : Colors.grey[700]),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          if (i < routes.length - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }

  /// 타임라인 시작/끝 지점
  Widget _buildTimelinePoint(
    String label, {
    bool isStart = false,
    bool isEnd = false,
  }) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isStart ? Colors.green : (isEnd ? Colors.red : Colors.grey),
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// 타임라인 구간 (도보/버스)
  Widget _buildTimelineSegment(
    RouteSegment segment, {
    required int segmentIndex,
    required bool isCurrent,
    required bool isPassed,
  }) {
    final isWalk = segment.moveType == "WALK";
    final baseColor = isWalk ? Colors.green : Colors.blue;
    final color = isPassed ? Colors.grey : baseColor;
    final icon = isWalk ? Icons.directions_walk : Icons.directions_bus;
    final label = isWalk ? "도보" : "버스 ${segment.transportName ?? ''}";

    return GestureDetector(
      onTap: () => onSegmentTap?.call(segmentIndex),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 왼쪽: 세로 라인
            SizedBox(
              width: 20,
              child: Column(
                children: [Expanded(child: Container(width: 3, color: color))],
              ),
            ),
            const SizedBox(width: 12),

            // 오른쪽: 구간 정보 카드
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isPassed ? 0.1 : 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isCurrent ? Colors.yellowAccent : color,
                    width: isCurrent ? 3 : 2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 구간 헤더 (아이콘 + 라벨)
                    Row(
                      children: [
                        Icon(icon, color: color, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: TextStyle(
                            color: color,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isCurrent) ...[
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.yellowAccent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              "현재",
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                        if (segment.description.isNotEmpty && !isCurrent) ...[
                          const Spacer(),
                          Text(
                            segment.description,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),

                    // 버스 구간: 승하차 정류장
                    if (!isWalk &&
                        (segment.startStation != null ||
                            segment.endStation != null)) ...[
                      const SizedBox(height: 12),
                      if (segment.startStation != null)
                        _buildStationRow(
                          icon: Icons.arrow_circle_up,
                          label: "승차",
                          stationName: segment.startStation!,
                          stationColor: Colors.green,
                          isPassed: isPassed,
                        ),
                      const SizedBox(height: 6),
                      if (segment.endStation != null)
                        _buildStationRow(
                          icon: Icons.arrow_circle_down,
                          label: "하차",
                          stationName: segment.endStation!,
                          stationColor: Colors.red,
                          isPassed: isPassed,
                        ),
                    ],

                    // 버스 정류장 목록 (현재 구간만)
                    if (!isWalk &&
                        segment.stations.isNotEmpty &&
                        isCurrent) ...[
                      const SizedBox(height: 12),
                      _buildStationList(segment),
                    ],

                    // 도보: 세부 단계
                    if (isWalk && segment.stepDescription.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...segment.stepDescription.asMap().entries.map((entry) {
                        final stepIndex = entry.key;
                        final step = entry.value;
                        final isCurrentStep =
                            isCurrent && stepIndex == currentStepIndex;
                        final isPassedStep =
                            isPassed ||
                            (isCurrent && stepIndex < currentStepIndex);

                        return Padding(
                          padding: const EdgeInsets.only(left: 4, top: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.only(top: 6),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isCurrentStep
                                      ? Colors.yellowAccent
                                      : (isPassedStep
                                            ? Colors.grey
                                            : Colors.grey[400]),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  step,
                                  style: TextStyle(
                                    color: isCurrentStep
                                        ? Colors.yellowAccent
                                        : (isPassedStep
                                              ? Colors.grey
                                              : Colors.grey[300]),
                                    fontSize: 14,
                                    fontWeight: isCurrentStep
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationRow({
    required IconData icon,
    required String label,
    required String stationName,
    required Color stationColor,
    required bool isPassed,
  }) {
    return Row(
      children: [
        Icon(icon, color: isPassed ? Colors.grey : stationColor, size: 20),
        const SizedBox(width: 8),
        Text(
          "$label: ",
          style: TextStyle(
            color: isPassed ? Colors.grey : stationColor,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        Expanded(
          child: Text(
            stationName,
            style: TextStyle(
              color: isPassed ? Colors.grey : Colors.white,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStationList(RouteSegment segment) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "정류장 (${segment.stations.length}개)",
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          ...segment.stations.asMap().entries.map((entry) {
            final index = entry.key;
            final station = entry.value;
            final isFirst = index == 0;
            final isLast = index == segment.stations.length - 1;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFirst
                          ? Colors.green
                          : (isLast ? Colors.red : Colors.grey[600]),
                    ),
                    child: Center(
                      child: Text(
                        "${index + 1}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      station.name,
                      style: TextStyle(
                        color: isFirst || isLast
                            ? Colors.white
                            : Colors.grey[400],
                        fontSize: 13,
                        fontWeight: isFirst || isLast
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
