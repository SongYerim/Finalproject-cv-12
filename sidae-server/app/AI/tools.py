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
                "사용자가 '지금 어디까지 왔어', '다음 단계 뭐야', '제대로 가고 있어'처럼 "
                "경로 진행/다음 안내가 필요한 질문을 하면 호출하세요. "
                "반환 예: {progress_percentage, next_step_description}"
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
                "사용자가 '몇 번 버스 타', '어디서 내려', '이 버스 맞아'처럼 "
                "탑승/하차 버스 정보가 필요한 질문을 하면 호출하세요. "
                "반환 예: {bus_number, boarding_stop, alighting_stop, remaining_stops}"
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
                "사용자가 '지금 어디야', '정류장 근처야'처럼 "
                "현재 위치 확인이 필요하면 호출하세요. "
                "반환 예: {lat, lon, address}"
            ),
            "parameters": {"type": "object", "properties": {}, "required": []}
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_detailed_distances",
            "description": (
                "세분화된 거리 정보를 조회합니다. "
                "사용자가 '얼마나 남았어', '정류장까지 얼마나 걸려', '버스 타려면 멀었어'처럼 "
                "거리 정보가 필요할 때 호출하세요. "
                "반환 예: {distance_to_boarding_stop, distance_to_alighting_stop, distance_to_destination}"
            ),
            "parameters": {"type": "object", "properties": {}, "required": []}
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_orientation_info",
            "description": (
                "방향 및 방위 정보를 조회합니다. "
                "사용자가 '지금 맞게 가고 있어?', '어디로 가야 해?', '몇 시 방향이야?'처럼 "
                "방향 안내가 필요할 때 호출하세요. "
                "반환 예: {clock_direction, target_direction, device_heading}"
            ),
            "parameters": {"type": "object", "properties": {}, "required": []}
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_upcoming_path",
            "description": (
                "앞으로 남은 전체 경로(구간) 목록을 조회합니다. "
                "사용자가 '앞으로 어떻게 가야 해?', '버스 내리고 나서 뭐 타?', '전체 경로 알려줘'처럼 "
                "미래의 경로 계획이 궁금할 때 호출하세요. "
                "반환 예: {upcoming_segments: ['도보 5분', '143번 버스', '도보 3분']}"
            ),
            "parameters": {"type": "object", "properties": {}, "required": []}
        }
    },
    {
        "type": "function",
        "function": {
            "name": "check_route_deviation",
            "description": (
                "경로 이탈 여부를 확인합니다. "
                "사용자가 '나 길 잃은 것 같아', '경로에서 벗어났어?'라고 물을 때 호출하세요. "
                "반환 예: {is_off_path, deviation_distance}"
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
            "progress_percentage": f"{context.get('progress', 0)}%",
            "next_step_description": context.get("current_step", "정보 없음")
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

    elif tool_name == "get_detailed_distances":
        return {
            "distance_to_boarding_stop": context.get("distance_to_boarding_stop", "해당 없음"),
            "distance_to_alighting_stop": context.get("distance_to_alighting_stop", "해당 없음"),
            "distance_to_destination": f"{context.get('distance_to_destination', 0)}m"
        }
        
    elif tool_name == "get_orientation_info":
        return {
            "clock_direction": context.get("clock_direction", "정보 없음"), # 예: "2시 방향"
            "target_direction": context.get("target_direction", "정보 없음"), # 예: "오른쪽 앞"
            "device_heading": context.get("device_heading"),
            "target_bearing": context.get("target_bearing")
        }

    elif tool_name == "get_upcoming_path":
        return {
            "upcoming_segments": context.get("upcoming_segments", []),
            "total_remaining_segments": len(context.get("upcoming_segments", []))
        }

    elif tool_name == "check_route_deviation":
        return {
            "is_off_path": context.get("is_off_path", False),
            "deviation_distance": context.get("deviation_distance", 0), # meter
            "message": "경로를 벗어났습니다." if context.get("is_off_path") else "정상 경로로 이동 중입니다."
        }
    
    return {"error": f"알 수 없는 tool: {tool_name}"}


def get_tool_result_string(tool_name: str, context: Dict[str, Any]) -> str:
    """Tool 실행 결과를 JSON 문자열로 반환"""
    result = execute_tool(tool_name, context)
    return json.dumps(result, ensure_ascii=False)
