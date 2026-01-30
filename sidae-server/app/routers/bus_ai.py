from app.AI.prompt import PromptManager
import logging
from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from app.AI.vlm_service import request_vlm_prediction
import json

# 로거 설정 (Cloud Run 로그에서 확인 용이)
logger = logging.getLogger("uvicorn")

router = APIRouter(
    tags=["Bus AI"]
)

@router.post("/bus-recognition")
async def identify_bus(file: UploadFile = File(...), mode: str = Form(...)):
    # 1. 파일 확장자 검증
    if not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="이미지 파일만 업로드 가능합니다.")

    try:
        image_bytes = await file.read()

        prompt_data = PromptManager.get_prompt(mode)

        system_instruction = prompt_data.get("system", "") 
        user_instruction = prompt_data.get("user", "")

        # 3. Vertex AI 엔드포인트 호출
        logger.info(f"Vertex AI 요청 시작: 파일명={file.filename}, 크기={len(image_bytes)} bytes")
        
        result = await request_vlm_prediction(
            image_bytes=image_bytes, 
            mime_type=file.content_type,
            system_prompt=system_instruction,
            user_prompt=user_instruction
        )
        
        logger.info(f"Vertex AI 응답 수신: {result}")

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
            final_data = {
                "found": False,
                "error": "Parsing Failed",
                "raw_text": raw_text_content
            }

        # [수정] 응답 구조를 범용적으로 변경
        return {
            "status": "success",
            "mode": mode,
            "result": final_data
        }
        
    except HTTPException as he:
        # 이미 정의된 HTTP 예외는 그대로 전달
        raise he
    except Exception as e:
        # 예측하지 못한 서버 내부 오류 로깅
        logger.error(f"버스 인식 중 오류 발생: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))