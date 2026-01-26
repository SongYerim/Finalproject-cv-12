// 버스 정보 관련 데이터 모델

/// 버스 정류장 정보
class BusStopInfo {
  final String busNumber;
  final String stationName;
  final double lat;
  final double lng;
  final int segmentIndex; // 어느 segment에서 발생했는지

  BusStopInfo({
    required this.busNumber,
    required this.stationName,
    required this.lat,
    required this.lng,
    required this.segmentIndex,
  });
}

/// 버스 도착 정보 (API 응답)
class BusArrivalInfo {
  final String busNumber;
  final String stationName;
  final String statusMsg; // "곧 도착", "3분20초후" 등
  final String plateNo;
  final String vehId;
  final String stationSeq;

  BusArrivalInfo({
    required this.busNumber,
    required this.stationName,
    required this.statusMsg,
    required this.plateNo,
    required this.vehId,
    required this.stationSeq,
  });

  factory BusArrivalInfo.fromJson(Map<String, dynamic> json) {
    return BusArrivalInfo(
      busNumber: json['bus_number'] ?? '',
      stationName: json['station_name'] ?? '',
      statusMsg: json['status_msg'] ?? '',
      plateNo: json['plate_no'] ?? '',
      vehId: json['veh_id'] ?? '',
      stationSeq: json['station_seq']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bus_number': busNumber,
      'station_name': stationName,
      'status_msg': statusMsg,
      'plate_no': plateNo,
      'veh_id': vehId,
      'station_seq': stationSeq,
    };
  }
}
