# app/AI/tools.py
"""
VLM Function Calling을 위한 Tool 정의
시각장애인 네비게이션 앱의 컨텍스트 정보를 VLM에 제공
"""
import json
from typing import Dict, Any, List

# Tool 정의 (OpenAI 호환 형식)
NAVIGATION_TOOLS: List[Dict[str, Any]] = [
    {
        "type": "function",
        "function": {
            "name": "get_navigation_context",
            "description": "현재 네비게이션 상태를 조회합니다. 목적지, 진행률, 현재 단계, 이동 수단 등의 정보를 반환합니다.",
            "parameters": {
                "type": "object",
                "properties": {},
                "required": []
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_target_bus_info",
            "description": "사용자가 탑승해야 할 버스 정보를 조회합니다. 버스 번호, 하차 정류장 등을 반환합니다.",
            "parameters": {
                "type": "object",
                "properties": {},
                "required": []
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_current_location",
            "description": "현재 위치 정보를 조회합니다. 좌표와 주소 정보를 반환합니다.",
            "parameters": {
                "type": "object",
                "properties": {},
                "required": []
            }
        }
    }
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
            return {"message": "현재 버스 정보가 없습니다."}
        return {
            "bus_number": bus_number,
            "destination_stop": context.get("destination_stop", "정보 없음"),
            "remaining_stops": context.get("remaining_stops", "정보 없음")
        }
    
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
    
    return {"error": f"알 수 없는 tool: {tool_name}"}


def get_tool_result_string(tool_name: str, context: Dict[str, Any]) -> str:
    """Tool 실행 결과를 JSON 문자열로 반환"""
    result = execute_tool(tool_name, context)
    return json.dumps(result, ensure_ascii=False)
