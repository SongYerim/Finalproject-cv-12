import httpx
import json
import os
import re
import logging
from datetime import datetime
from typing import Dict, Any, List, Optional
from fastapi import HTTPException, status

logger = logging.getLogger(__name__)

class SkTransitService:
    TRANSIT_URL = "https://apis.openapi.sk.com/transit/routes"
    PEDESTRIAN_URL = "https://apis.openapi.sk.com/tmap/routes/pedestrian?version=1"
    POI_URL = "https://apis.openapi.sk.com/tmap/pois"

    TURN_TYPE_MAP = {
        11: "직진", 12: "좌회전", 13: "우회전", 14: "유턴",
        16: "8시 방향 좌회전", 17: "10시 방향 좌회전",
        18: "2시 방향 우회전", 19: "4시 방향 우회전",
        125: "육교", 126: "지하보도", 127: "계단 진입", 128: "경사로 진입",
        211: "횡단보도", 212: "좌측 횡단보도", 213: "우측 횡단보도",
        214: "8시 방향 횡단보도", 215: "10시 방향 횡단보도",
        216: "2시 방향 횡단보도", 217: "4시 방향 횡단보도",
        218: "엘리베이터", 200: "출발", 201: "도착",
        233: "직진"
    }

    def __init__(self, client: httpx.AsyncClient, api_key: str):
        self.client = client
        self.headers = {
            "appKey": api_key,
            "Content-Type": "application/json",
            "Accept": "application/json"
        }

    # _save_log 제거 (사용되지 않음/불필요)

    def _format_description(self, turn_type: int, raw_desc: str) -> str:
        """
        1. "보행자도로를 따라 27m 이동" -> "27m 이동"
        2. "자하문로, 60m" -> "60m 이동"
        3. 앞에 [회전타입] 붙이기
        """
        dist_str = raw_desc
        
        # 1. 정규식으로 숫자+m 패턴 찾기 (예: 27m, 1.5km)
        match = re.search(r'(\d+m)', raw_desc)
        if match:
            dist_str = match.group(1) # "27m"
        else:
            # m단위가 없으면 쉼표 로직 시도 (Fallback)
            if "," in raw_desc:
                try:
                    dist_str = raw_desc.split(",")[1].strip()
                except: pass
        
        # "이동" 글자 붙이기
        if "이동" not in dist_str and dist_str.endswith("m"):
             dist_str += " 이동"

        # 2. TurnType 문구 붙이기
        turn_text = self.TURN_TYPE_MAP.get(turn_type, "")

        # 횡단보도
        if 211 <= turn_type <= 217:
            return f"[횡단보도]에서 {dist_str}"
        # 회전
        elif turn_type in [12, 13, 14, 16, 17, 18, 19]:
            return f"[{turn_text}] 후 {dist_str}"
        # 시설물
        elif turn_type in [125, 126, 127, 128, 129, 218]:
            return f"[{turn_text}] 이용하여 {dist_str}"
        # 출발/도착
        elif turn_type in [200, 201]:
             return f"[{turn_text}] {dist_str}"
        # 그 외 (직진 등)
        else:
            return dist_str

    async def search_transit_route(self, start_lat, start_lng, end_lat, end_lng) -> Dict[str, Any]:
        payload = {"startX": str(start_lng), "startY": str(start_lat), "endX": str(end_lng), "endY": str(end_lat), "lang": 0, "format": "json", "count": 10}
        
        try:
            response = await self.client.post(self.TRANSIT_URL, headers=self.headers, json=payload)
            response.raise_for_status()
            data = response.json()
            if "metaData" not in data: 
                raise HTTPException(status_code=404, detail="경로 없음")
            return data
        except httpx.HTTPStatusError as e:
            logger.error(f"Transit API Error: {e}")
            raise HTTPException(status_code=500, detail="TMAP Transit API Error")
        except Exception as e:
            logger.error(f"Transit Unexpected Error: {e}")
            raise HTTPException(status_code=500, detail="Server Error")

    def _parse_pedestrian_features(self, features: List[Dict[str, Any]]) -> Dict[str, Any]:
        """
        API 응답의 features 리스트를 파싱하여 도보 경로 데이터를 생성합니다.
        """
        path_points = []
        steps = []
        current_step = None 

        total_time = 0
        total_distance = 0
        if features:
            first_props = features[0].get('properties', {})
            total_time = first_props.get('totalTime', 0)
            total_distance = first_props.get('totalDistance', 0)

        for feature in features:
            geometry = feature.get('geometry', {})
            props = feature.get('properties', {})
            geo_type = geometry.get('type')

            if geo_type == 'Point':
                pt_lat = float(geometry['coordinates'][1])
                pt_lng = float(geometry['coordinates'][0])
                path_points.append([pt_lat, pt_lng])

                turn_type = int(props.get("turnType", 0))
                
                # ✨ [수정] Point 설명도 _format_description 통과
                desc = ""
                if turn_type in [200, 201]:
                        raw_desc = props.get("description", "")
                        desc = self._format_description(turn_type, raw_desc)

                current_step = {
                    "description": desc,
                    "turnType": turn_type,
                    "facilityType": props.get("facilityType", ""),
                    "roadType": 0,
                    "time": 0,
                    "distance": 0,
                    "lat": pt_lat,
                    "lng": pt_lng,
                    "path": [] 
                }
                steps.append(current_step)

            elif geo_type == 'LineString':
                coords = geometry['coordinates']

                # Step 분리 로직
                if current_step is not None and len(current_step["path"]) > 0:
                    new_start_lat = float(coords[0][1])
                    new_start_lng = float(coords[0][0])
                    
                    virtual_turn_type = 233
                    raw_line_desc = props.get("description", "")
                    
                    # ✨ [수정] 가상 스텝 설명도 _format_description 통과
                    formatted_desc = self._format_description(virtual_turn_type, raw_line_desc)

                    new_step = {
                        "description": formatted_desc,
                        "turnType": virtual_turn_type,
                        "facilityType": props.get("facilityType", ""),
                        "roadType": 0,
                        "time": 0,
                        "distance": 0,
                        "lat": new_start_lat,
                        "lng": new_start_lng,
                        "path": []
                    }
                    steps.append(new_step)
                    current_step = new_step

                if current_step is not None:
                    line_road_type = int(props.get("roadType", 0))
                    if line_road_type > 0: current_step["roadType"] = line_road_type
                    
                    step_time = int(props.get("time", 0))
                    if step_time > 0: current_step["time"] += step_time
                        
                    step_dist = int(props.get("distance", 0))
                    if step_dist > 0: current_step["distance"] += step_dist

                    # Point에서 생성된 스텝(아직 경로 없는)의 경우 설명 업데이트
                    if len(current_step["path"]) == 0:
                        current_turn = current_step["turnType"]
                        
                        # 출발/도착이 아니면 LineString 설명으로 교체하되 포맷팅 적용
                        if current_turn not in [200, 201]:
                            raw_line_desc = props.get("description", "")
                            current_step["description"] = self._format_description(current_turn, raw_line_desc)

                for coord in coords:
                    lat, lng = float(coord[1]), float(coord[0])
                    path_points.append([lat, lng])
                    if current_step is not None:
                        current_step["path"].append([lat, lng])

        return {
            "path": path_points,
            "steps": steps,
            "overview": {"totalTime": total_time, "totalDistance": total_distance}
        }

    async def search_pedestrian_route(
        self,
        start_lat: float,
        start_lng: float,
        end_lat: float,
        end_lng: float
    ) -> Dict[str, Any]:
        
        payload = {
            "startX": str(start_lng), "startY": str(start_lat),
            "endX": str(end_lng), "endY": str(end_lat),
            "reqCoordType": "WGS84GEO", "resCoordType": "WGS84GEO",
            "startName": "출발", "endName": "도착", "searchOption": "0"
        }

        try:
            response = await self.client.post(self.PEDESTRIAN_URL, headers=self.headers, json=payload)
            if response.status_code != 200: return {} 

            data = response.json()
            features = data.get('features', [])
            
            # 파싱 로직 분리 호출
            return self._parse_pedestrian_features(features)

        except Exception as e:
            logger.error(f"Pedestrian API Error: {e}")
            return {}

    async def search_poi(self, keyword: str) -> List[Dict[str, Any]]:
        # (기존 동일)
        params = {"version": "1", "searchKeyword": keyword, "resCoordType": "WGS84GEO", "reqCoordType": "WGS84GEO", "count": 20}
        
        try:
            response = await self.client.get(self.POI_URL, headers=self.headers, params=params)
            if response.status_code != 200: return []
            data = response.json()
            pois = data.get('searchPoiInfo', {}).get('pois', {}).get('poi', [])
            results = []
            for poi in pois:
                results.append({"name": poi.get('name'), "address": f"{poi.get('upperAddrName', '')} {poi.get('middleAddrName', '')} {poi.get('lowerAddrName', '')}".strip(), "latitude": float(poi.get('noorLat')), "longitude": float(poi.get('noorLon'))})
            return results
        except Exception as e:
            logger.error(f"TMAP POI Search Error: {e}")
            return []