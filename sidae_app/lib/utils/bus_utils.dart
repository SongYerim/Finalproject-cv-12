/// 버스 관련 유틸리티 함수
///
/// 여러 화면에서 공통으로 사용되는 버스 관련 함수들을 모아놓은 파일입니다.

/// "곧 도착" 상태인지 확인
///
/// 버스 도착 상태 메시지에서 "곧 도착", "잠시 후", "1분", "2분" 등의
/// 키워드가 포함되어 있는지 확인합니다.
bool isBusApproachingStatus(String statusMsg) {
  return statusMsg.contains('곧 도착') ||
      statusMsg.contains('1분') ||
      statusMsg.contains('2분') ||
      statusMsg.contains('3분') ||
      statusMsg.contains('4분') ||
      statusMsg.contains('5분') ||
      statusMsg.contains('6분') ||
      statusMsg.contains('7분') ||
      statusMsg.contains('8분') ||
      statusMsg.contains('9분') ||
      statusMsg.contains('10분') ||
      statusMsg.contains('11분') ||
      statusMsg.contains('12분') ||
      statusMsg.contains('13분') ||
      statusMsg.contains('14분') ||
      statusMsg.contains('15분');
}
