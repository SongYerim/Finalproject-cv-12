import 'dart:math' as math;

/// 수학 관련 유틸리티 함수
///
/// 여러 화면에서 공통으로 사용되는 수학 관련 함수들을 모아놓은 파일입니다.

/// 각도 정규화: 360도 wrap-around 시 짧은 경로로 회전
///
/// [newAngle]과 [prevAngle]을 비교하여 180도 이상 차이나면
/// 반대 방향이 더 짧으므로 각도를 조정합니다.
double normalizeAngle(double newAngle, double prevAngle) {
  double diff = newAngle - prevAngle;
  // 180도 이상 차이나면 반대 방향이 더 짧음
  if (diff > math.pi) {
    newAngle -= 2 * math.pi; // 360도 빼기
  } else if (diff < -math.pi) {
    newAngle += 2 * math.pi; // 360도 더하기
  }
  return newAngle;
}
