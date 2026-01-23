import logging
from typing import List, Dict, Any
from app.schemas.route_dto import RouteSegment, MoveType, StationInfo, RouteStep

logger = logging.getLogger(__name__)

class PathParser:
    # 📌 [수정됨] 정확한 TMAP 보행자 turnType 코드 매핑
    TURN_TYPE_MAP = {
        # 안내 없음 / 직진
        0: "", 1: "", 2: "", 3: "", 4: "", 5: "", 6: "", 7: "",
        11: "직진",
        233: "직진", # 임시 직진
        
        # ... (중략) ...
        # (기존 map 내용 유지, 너무 길어서 생략하려 했으나 replace tool 특성상 전체 변경이 안전할 수 있음. 
        # 하지만 startLine/endLine을 잘 조절하면 됨. 
        # 여기서는 파일 상단 import와 logger 설정부터 _parse_walk_leg 내부 수정까지 덮어야 함.
        # 차라리 import/logger 부분과 _parse_walk_leg 부분을 나눠서 하는게 나을 수도 있지만, 
        # 한번에 가능하면 한번에 함.)
    }
    # ... (TURN_TYPE_MAP 내용은 그대로 둠. 위 내용 무시하고 코드만 봄)
    
    # 앗, replace_file_content는 block replace임.
    # 나눠서 진행함.
    
    # 전략:
    # 1. 상단 import 추가
    # 2. _parse_walk_leg 내부 print 변경
    
    # 이 호출은 1번: 상단 import 및 logger 설정

    # 📌 [수정됨] 정확한 TMAP 보행자 turnType 코드 매핑
    TURN_TYPE_MAP = {
        # 안내 없음 / 직진
        0: "", 1: "", 2: "", 3: "", 4: "", 5: "", 6: "", 7: "",
        11: "직진",
        233: "직진", # 임시 직진

        # 방향 회전
        12: "좌회전",
        13: "우회전",
        14: "유턴",
        16: "8시 방향 좌회전",
        17: "10시 방향 좌회전",
        18: "2시 방향 우회전",
        19: "4시 방향 우회전",

        # 시설물 (보라색 계열)
        125: "육교",
        126: "지하보도",
        127: "계단 진입",
        128: "경사로 진입",
        129: "계단+경사로",
        218: "엘리베이터",

        # 횡단보도 (초록색 계열)
        211: "횡단보도",
        212: "좌측 횡단보도",
        213: "우측 횡단보도",
        214: "8시 방향 횡단보도",
        215: "10시 방향 횡단보도",
        216: "2시 방향 횡단보도",
        217: "4시 방향 횡단보도",

        # 경유지/출도착
        200: "출발",
        201: "도착",
        184: "경유", # 경유지
        185: "경유", 186: "경유", 187: "경유", 188: "경유", 189: "경유"
    }

    def __init__(self, sk_service=None):
        self.sk_service = sk_service

    async def parse(self, raw_data: Dict[str, Any]) -> List[RouteSegment]:
        if "metaData" not in raw_data or "plan" not in raw_data["metaData"]:
            return []

        itineraries = raw_data["metaData"]["plan"]["itineraries"]
        if not itineraries:
            return []
        
        best_route = itineraries[0]
        legs = best_route.get("legs", [])
        parsed_segments = []
        
        for index, leg in enumerate(legs):
            mode = leg.get("mode", "")
            if mode == "WALK":
                segment = await self._parse_walk_leg(index, leg)
            elif mode in ["BUS", "SUBWAY"]:
                segment = self._parse_transit_leg(index, leg, mode)
            else:
                continue
            parsed_segments.append(segment)
            
        return parsed_segments

    async def _parse_walk_leg(self, index: int, leg: Dict[str, Any]) -> RouteSegment:
        end_name = leg.get("end", {}).get("name", "목적지")
        distance = leg.get("distance", 0)
        duration = leg.get("sectionTime", 0)
        path_coordinates = self._extract_coordinates(leg)
        
        step_description_list = [] # 👈 변수명 명확화
        final_steps = []

        if distance > 50 and self.sk_service:
            try:
                logger.info(f"🚶‍♂️ [Detailed Walk] API Call... ({distance}m)")
                start_lat = float(leg['start']['lat'])
                start_lng = float(leg['start']['lon'])
                end_lat = float(leg['end']['lat'])
                end_lng = float(leg['end']['lon'])
                
                ped_data = await self.sk_service.search_pedestrian_route(
                    start_lat, start_lng, end_lat, end_lng
                )
                
                if ped_data and "path" in ped_data:
                    path_coordinates = ped_data["path"]
                    if "overview" in ped_data:
                        distance = ped_data["overview"].get("totalDistance", distance)
                        duration = ped_data["overview"].get("totalTime", duration)

                    raw_steps = ped_data.get("steps", [])
                    
                    for step in raw_steps:
                        desc = step.get("description", "")
                        turn_type = step.get("turnType", 0)
                        facility_type = step.get("facilityType", "")
                        
                        road_type = step.get("roadType", 0)
                        time_val = step.get("time", 0)
                        dist_val = step.get("distance", 0)
                        
                        lat = step.get("lat", 0.0)
                        lng = step.get("lng", 0.0)
                        step_path = step.get("path", [])

                        # 1. 객체 생성
                        final_steps.append(RouteStep(
                            description=desc,
                            lat=lat,
                            lng=lng,
                            turn_type=turn_type,
                            facility_type=facility_type,
                            road_type=road_type,
                            time=time_val,
                            distance=dist_val,
                            path=step_path
                        ))

                        # 2. 안내 텍스트 생성
                        turn_text = self.TURN_TYPE_MAP.get(turn_type, "")

                        # 중복 방지 후 추가
                        if not step_description_list or step_description_list[-1] != desc:
                            step_description_list.append(desc)

            except Exception as e:
                logger.error(f"⚠️ [Detailed Walk] Error: {e}")

        # Fallback (상세 정보 없으면 대략적인 정보 추가)
        if not step_description_list:
            step_description_list.append(f"{end_name}까지 약 {distance}m 이동")

        return RouteSegment(
            segment_index=index,
            move_type=MoveType.WALK,
            description=f"도보 이동 ({distance}m)",
            step_description=step_description_list, # 👈 리스트 전달
            steps=final_steps,
            distance=distance,
            duration=duration,
            path_coordinates=path_coordinates,
            stations=[]
        )

    def _parse_transit_leg(self, index: int, leg: Dict[str, Any], mode: str) -> RouteSegment:
        route_name = leg.get("route", "대중교통")
        if mode == "BUS" and ":" in route_name:
            route_name = route_name.split(":")[-1]
        start_station = leg.get("start", {}).get("name", "")
        end_station = leg.get("end", {}).get("name", "")
        station_list: List[StationInfo] = []
        if "passStopList" in leg and "stations" in leg["passStopList"]:
            for st in leg["passStopList"]["stations"]:
                station_list.append(StationInfo(index=int(st.get("index", 0)), name=st.get("stationName", ""), lat=float(st.get("lat", 0.0)), lng=float(st.get("lon", 0.0))))
        if not station_list:
             if "lat" in leg.get("start", {}): station_list.append(StationInfo(index=0, name=leg["start"].get("name", ""), lat=float(leg["start"]["lat"]), lng=float(leg["start"]["lon"])))
             if "lat" in leg.get("end", {}): station_list.append(StationInfo(index=999, name=leg["end"].get("name", ""), lat=float(leg["end"]["lat"]), lng=float(leg["end"]["lon"])))

        return RouteSegment(
            segment_index=index, move_type=MoveType.BUS if mode == "BUS" else MoveType.SUBWAY,
            description=f"{start_station}에서 {route_name} 승차", instructions=[f"{end_station} 방향으로 이동"],
            transport_name=route_name, start_station=start_station, end_station=end_station,
            distance=leg.get("distance", 0), duration=leg.get("sectionTime", 0),
            path_coordinates=self._extract_coordinates(leg), stations=station_list
        )

    def _extract_coordinates(self, leg: Dict[str, Any]) -> List[List[float]]:
        return self._parse_linestring(leg.get("passShape", {}).get("linestring", ""))

    def _parse_linestring(self, coords_str: str) -> List[List[float]]:
        if not coords_str: return []
        path_list = []
        for point in coords_str.split(" "):
            if "," in point:
                try:
                    lng, lat = point.split(",")
                    path_list.append([float(lat), float(lng)])
                except ValueError:
                    logger.warning(f"Invalid coordinate format: {point}")
                    continue
        return path_list