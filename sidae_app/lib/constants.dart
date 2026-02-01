/// 앱 전역 상수 정의

/// GPS 기반 근접 감지 임계값 (미터)
///
/// 사용처:
/// - 경로 탐색 (RouteTracker.passThreshold)
/// - 횡단보도 감지 (CrosswalkDetector.proximityThreshold)
/// - 버스 정류장 감지 (BusStopDetector.proximityThreshold)
const double kProximityThreshold = 15.0;
