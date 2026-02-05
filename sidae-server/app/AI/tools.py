# app/AI/tools.py
"""
VLM Function Calling을 위한 Tool 정의
시각장애인 네비게이션 앱의 컨텍스트 정보를 VLM에 제공
"""
import json
from typing import Dict, Any, List

# Tool 정의 (OpenAI 호환 형식)
NAVIGATION_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "get_navigation_context",
            "description": (
                "현재 네비게이션 진행 상태를 조회합니다. "
                "사용자가 '지금 어디까지 왔어?', '다음 단계 뭐야?', '제대로 가고 있어?'처럼 "
                "경로 진행/다음 안내가 필요한 질문을 하면 호출하세요. "
                "반환 예: {destination, mode, current_step, progress, next_instruction}"
            ),
            "parameters": {"type": "object", "properties": {}, "required": []}
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_target_bus_info",
            "description": (
                "사용자가 탑승해야 할 버스 정보를 조회합니다. "
                "사용자가 '몇 번 버스 타?', '어디서 내려?', '이 버스 맞아?'처럼 "
                "탑승/하차 버스 정보가 필요한 질문을 하면 호출하세요. "
                "반환 예: {bus_number, boarding_stop, alighting_stop, direction}"
            ),
            "parameters": {"type": "object", "properties": {}, "required": []}
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_current_location",
            "description": (
                "현재 위치를 조회합니다. "
                "사용자가 '지금 어디야?', '정류장 근처야?', '길을 잘못 든 것 같아'처럼 "
                "현재 위치 확인이나 경로 이탈 판단이 필요하면 호출하세요. "
                "반환 예: {lat, lon, address}"
            ),
            "parameters": {"type": "object", "properties": {}, "required": []}
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_remaining_distance",
            "description": (
                "목적지까지 남은 거리와 시간을 조회합니다. "
                "사용자가 '얼마나 남았어?', '멀었어?', '도착까지 몇 분 걸려?'처럼 "
                "남은 거리나 소요 시간이 궁금할 때 호출하세요. "
                "반환 예: {remaining_distance, remaining_time_seconds, current_destination}"
            ),
            "parameters": {"type": "object", "properties": {}, "required": []}
        }
    },
]


def execute_tool(tool_name: str, context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Tool 호출 실행. 앱에서 전달받은 context에서 필요한 데이터를 추출하여 반환.
    
    Args:
        tool_name: 호출할 tool 이름
        context: 앱에서 전달받은 컨텍스트 JSON
    
    Returns:
        Tool 실행 결과 (dict)
    """
    if tool_name == "get_navigation_context":
        return {
            "destination": context.get("destination", "알 수 없음"),
            "progress": f"{context.get('progress', 0)}%",
            "current_step": context.get("current_step", "정보 없음"),
            "transport_type": context.get("transport_type", "도보"),
            "is_on_bus": context.get("is_on_bus", False)
        }
    
    elif tool_name == "get_target_bus_info":
        bus_number = context.get("bus_number")
        if not bus_number:
            return {"message": "현재 버스 정보가 없습니다. 이 경로에는 버스 구간이 없을 수 있습니다."}
        
        remaining = context.get("remaining_stops", 0)
        total = context.get("total_stops", 0)
        is_on_bus = context.get("is_on_bus", False)
        
        result = {
            "bus_number": bus_number,
            "start_station": context.get("start_station", "정보 없음"),  # 승차 정류장
            "destination_stop": context.get("destination_stop", "정보 없음"),  # 하차 정류장
            "total_stops": total,  # 전체 정류장 수
            "remaining_stops": remaining if is_on_bus else f"탑승 전 (총 {total}개 정류장)",  # 남은 정류장
            "is_on_bus": is_on_bus
        }
        
        # 정류장 목록이 있으면 추가
        station_names = context.get("station_names", [])
        if station_names:
            result["station_list"] = station_names
        
        return result
    
    elif tool_name == "get_current_location":
        lat = context.get("latitude")
        lng = context.get("longitude")
        if lat is None or lng is None:
            return {"message": "위치 정보를 가져올 수 없습니다."}
        return {
            "latitude": lat,
            "longitude": lng,
            "address": context.get("address", "주소 정보 없음")
        }

    elif tool_name == "get_remaining_distance":
        dist = context.get("remaining_distance", 0)
        time = context.get("remaining_time", 0)
        # 하차 정류장이 있으면 그것을, 없으면 최종 목적지를 목표로 표시
        dest = context.get("destination_stop") if context.get("destination_stop") else context.get("destination", "알 수 없는 목적지")
        
        return {
            "current_destination": dest,
            "remaining_distance": f"{dist}m",
            "remaining_time_seconds": time,
            "remaining_time_formatted": f"{time // 60}분 {time % 60}초" if time >= 60 else f"{time}초"
        }
    
    return {"error": f"알 수 없는 tool: {tool_name}"}


def get_tool_result_string(tool_name: str, context: Dict[str, Any]) -> str:
    """Tool 실행 결과를 JSON 문자열로 반환"""
    result = execute_tool(tool_name, context)
    return json.dumps(result, ensure_ascii=False)
