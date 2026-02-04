import 'package:flutter/material.dart';
import '../services/bus_popup_state_service.dart';
import '../services/bus_arrival_service.dart';

/// 버스 도착 오버레이 위젯
///
/// 버스 정류장에서 버스 도착 정보를 표시하는 오버레이입니다.
/// 4.dart와 5.dart에서 공통으로 사용됩니다.
class BusArrivalOverlay extends StatelessWidget {
  final BusPopupStateService popupState;
  final VoidCallback onClose;

  const BusArrivalOverlay({
    super.key,
    required this.popupState,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 100,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).primaryColor, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 간소화된 헤더
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  popupState.busStationName ?? '버스 정류장',
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    // 새로고침 버튼 + 카운트다운
                    StreamBuilder<int>(
                      stream: BusArrivalService.instance.countdownStream,
                      initialData: 30,
                      builder: (context, snapshot) {
                        final remaining = snapshot.data ?? 30;
                        return TextButton.icon(
                          onPressed: () {
                            BusArrivalService.instance.refresh();
                          },
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
                            size: 14,
                          ),
                          label: Text(
                            '${remaining}초',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.grey,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: onClose,
                    ),
                  ],
                ),
              ],
            ),
            if (popupState.busArrival != null) ...[
              // 버스 번호 + 남은 시간 (한 줄로)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      popupState.busArrival!.busNumber,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    popupState.busArrival!.statusMsg,
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ] else
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(
                    color: Colors.blue,
                    strokeWidth: 2,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
