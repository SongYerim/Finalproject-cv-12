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
            # VLM 모드: Function Calling 사용
            context_dict = json.loads(context) if context else {}
            
            # Tool calling 활성화된 경우
            if context:
                logger.info(f"VLM with Tools 요청: context={context_dict}")
                vlm_prompt_with_format = vlm_prompt + ' 출력 형식 (반드시 이 형식을 따르세요):{"description": }'
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
                vlm_prompt += '출력 형식 (반드시 이 형식을 따르세요):{"description": }'
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

        final_data = {}
        
        try:
            # 1. 마크다운 코드블록 제거 (```json ... ```)
            clean_text = raw_text_content.replace("```json", "").replace("```", "").strip()
            
            # 2. 문자열을 진짜 딕셔너리(객체)로 변환
            final_data = json.loads(clean_text)
            
        except json.JSONDecodeError:
            # 파싱 실패 시 (AI가 이상한 텍스트를 줬을 때)
            logger.warning(f"JSON 파싱 실패. 원본 텍스트 반환. Raw: {raw_text_content}")
            return {
                "des": "AI 응답을 해석할 수 없습니다.",
                "reason": "데이터 형식 오류", 
                "raw_text": raw_text_content, # 디버깅용: AI가 뭐라고 했는지 확인
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