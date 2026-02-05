from app.AI.prompt import PromptManager
import logging
from typing import Optional
from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from app.AI.vlm_service import request_vlm_prediction, request_vlm_prediction_with_tools
from app.AI.tools import NAVIGATION_TOOLS
import json

# 로거 설정 (Cloud Run 로그에서 확인 용이)
logger = logging.getLogger("uvicorn")

router = APIRouter(tags=["Bus AI"])


def _format_tool_result(tool_name: str, result: dict) -> str:
    """
    Tool 실행 결과를 시각장애인이 듣기 좋은 자연어로 변환
    """
    if "error" in result:
        return f"정보를 가져오는데 실패했어요. {result.get('error', '')}"
    
    if "message" in result:
        return result["message"]
    
    if tool_name == "get_navigation_context":
        dest = result.get("destination", "목적지")
        progress = result.get("progress", "0%")
        step = result.get("current_step", "")
        return f"현재 {dest}까지 {progress} 진행했어요. {step}"
    
    elif tool_name == "get_target_bus_info":
        bus = result.get("bus_number", "버스")
        dest_stop = result.get("destination_stop", "")
        remaining = result.get("remaining_stops", "")
        is_on = result.get("is_on_bus", False)
        
        if is_on:
            return f"{bus}번 버스 탑승 중이에요. {dest_stop}까지 {remaining}개 정류장 남았어요."
        else:
            return f"{bus}번 버스를 타야 해요. {dest_stop}에서 내리면 돼요."
    
    elif tool_name == "get_current_location":
        addr = result.get("address", "현재 위치")
        return f"현재 위치는 {addr} 근처예요."
    
    elif tool_name == "get_remaining_distance":
        dest = result.get("current_destination", "목적지")
        dist = result.get("remaining_distance", "")
        time_fmt = result.get("remaining_time_formatted", "")
        return f"{dest}까지 약 {dist}, {time_fmt} 정도 남았어요."
    
    # 기본: JSON을 문자열로 반환
    return str(result)

@router.post("/bus-recognition")
async def identify_bus(
    file: UploadFile = File(...), 
    mode: str = Form(...), 
    vlm_prompt: Optional[str] = Form(None),
    context: Optional[str] = Form(None)  # 앱 컨텍스트 (JSON 문자열)
):
    # 1. 파일 확장자 검증
    if not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="이미지 파일만 업로드 가능합니다.")

    try:
        image_bytes = await file.read()

        prompt_data = PromptManager.get_prompt(mode)

        system_instruction = prompt_data.get("system", "") 
        user_instruction = prompt_data.get("user", "")
        token_limit = prompt_data.get("max_tokens", 300)
        # 3. Vertex AI 엔드포인트 호출
        logger.info(f"Vertex AI 요청 시작: 파일명={file.filename}, 크기={len(image_bytes)} bytes")
        
        if vlm_prompt and vlm_prompt.strip() and vlm_prompt.strip().lower() != "null":
            # VLM 모드: Function Calling 방식 (Option B - Agentic)
            context_dict = json.loads(context) if context else {}
            
            # Tool calling 활성화된 경우 (context가 있을 때)
            if context:
                logger.info(f"VLM with Tools 요청: context={context_dict}")
                vlm_prompt_with_format = vlm_prompt # 도구 사용 시에는 Tool Call을 유도하기 위해 포맷 강제 제거
                result_ = await request_vlm_prediction_with_tools(
                    image_bytes=image_bytes, 
                    mime_type=file.content_type,
                    system_prompt=system_instruction,
                    user_prompt=vlm_prompt_with_format,
                    tools=NAVIGATION_TOOLS,
                    context=context_dict,
                    max_tokens=token_limit
                )
            else:
                # 기존 방식 (context 없는 경우)
                vlm_prompt += ' 출력 형식 (반드시 이 형식을 따르세요):{"description": }'
                result_ = await request_vlm_prediction(
                    image_bytes=image_bytes, 
                    mime_type=file.content_type,
                    system_prompt=system_instruction,
                    user_prompt=vlm_prompt,
                    max_tokens=token_limit
                )

        else:
            result_ = await request_vlm_prediction(
                image_bytes=image_bytes, 
                mime_type=file.content_type,
                system_prompt=system_instruction,
                user_prompt=user_instruction,
                max_tokens = token_limit
            )
            
        logger.info(f"Vertex AI 응답 수신: {result_}")
        result = result_[0]
        resize_time = result_[1]
        model_time = result_[2]
        choices = result.get("choices") # for OpenAI style response

        if choices and len(choices) > 0:
            # choices -> 0번째 -> message -> content 경로가 표준입니다.
            raw_text_content = choices[0].get("message", {}).get("content", "")
        else:
            # choices가 비어있거나 없으면 에러 처리
            logger.error(f"유효하지 않은 응답 포맷: {result}")
            raw_text_content = "인식 실패 (응답 없음)"

        # VLM with Tools 모드: JSON 응답 후처리
        if vlm_prompt and vlm_prompt.strip() and vlm_prompt.strip().lower() != "null" and context:
            from app.AI.tools import execute_tool
            
            logger.info(f"VLM 원본 응답: {raw_text_content}")
            
            try:
                # JSON 파싱 (마크다운 코드블록 제거)
                clean_text = raw_text_content.replace("```json", "").replace("```", "").strip()
                vlm_response = json.loads(clean_text)
                
                action = vlm_response.get("action", "answer")
                tool_name = vlm_response.get("tool_name")
                response_text = vlm_response.get("response")
                
                logger.info(f"VLM 파싱 결과: action={action}, tool_name={tool_name}")
                
                # action이 "call_tool"인 경우: Tool 실행 후 결과 반환
                if action == "call_tool" and tool_name:
                    tool_result = execute_tool(tool_name, context_dict)
                    logger.info(f"Tool 실행 결과: {tool_result}")
                    
                    # Tool 결과를 자연어로 변환해서 반환
                    des = _format_tool_result(tool_name, tool_result)
                    return {
                        "des": des,
                        "tool_name": tool_name,
                        "tool_result": tool_result,
                        "resize_time": resize_time,
                        "model_time": model_time
                    }
                
                # action이 "answer"인 경우: 응답 텍스트 반환
                else:
                    return {
                        "des": response_text or raw_text_content,
                        "resize_time": resize_time,
                        "model_time": model_time
                    }
                    
            except json.JSONDecodeError:
                # JSON 파싱 실패 시 원본 텍스트 반환
                logger.warning(f"VLM JSON 파싱 실패. 원본 반환: {raw_text_content}")
                return {
                    "des": raw_text_content,
                    "resize_time": resize_time,
                    "model_time": model_time
                }

        # 기존 모드 (bell, tag 등): JSON 파싱 필요
        final_data = {}
        
        try:
            # 1. 마크다운 코드블록 제거 (```json ... ```)
            clean_text = raw_text_content.replace("```json", "").replace("```", "").strip()
            logger.info(f"clean_text: {clean_text}")   
            # 2. 문자열을 진짜 딕셔너리(객체)로 변환
            final_data = json.loads(clean_text)
            logger.info(f"final_data: {final_data}")   
        except json.JSONDecodeError:
            # 파싱 실패 시 (AI가 이상한 텍스트를 줬을 때)
            logger.warning(f"JSON 파싱 실패. 원본 텍스트 반환. Raw: {raw_text_content}")
            return {
                "des": raw_text_content, # 오류 메시지 대신 원본 텍스트를 그대로 반환
                "reason": "데이터 형식 오류 (Raw Text Fallback)", 
                "raw_text": raw_text_content, 
                "resize_time": resize_time, 
                "model_time": model_time
            }
        
        if mode in ['bell', 'tag']:
            pos = final_data.get("selected_area", " ")
            reason = final_data.get("reason", "이유 없음")
            if mode == 'bell':
                mode = '하차벨'
            elif mode == 'tag':
                mode ='태그기'
            if pos in ["카드 단말기 없음", "하차벨 없음"]:
                des = f'{mode} 위치를 못 찾겠습니다.'
            else:
                des = f'{mode} 위치는 {pos}에 있습니다.'
            return {"des": des, "reason": reason, "resize_time": resize_time, "model_time": model_time}
        elif mode in ['tag_']:
            mode = '태그기'
            pos = final_data.get("selected_area", " ")
            if pos == "카드 단말기 없음":
                des = "태그기 위치를 못 찾겠습니다."
            else:
                des = f'{mode} 위치는 {pos}에 있습니다.'
            return {"des": des, "resize_time": resize_time, "model_time": model_time}
        
        
        return {
            "result": final_data, "resize_time": resize_time, "model_time": model_time
        }
        
    except HTTPException as he:
        # 이미 정의된 HTTP 예외는 그대로 전달
        raise he
    except Exception as e:
        # 예측하지 못한 서버 내부 오류 로깅
        logger.error(f"버스 인식 중 오류 발생: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))