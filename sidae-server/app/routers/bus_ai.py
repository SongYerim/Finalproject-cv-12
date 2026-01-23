import logging
from fastapi import APIRouter, UploadFile, File, HTTPException
from app.AI.vlm_service import request_vlm_prediction

# 로거 설정 (Cloud Run 로그에서 확인 용이)
logger = logging.getLogger("uvicorn")

router = APIRouter(
    prefix="/ai",
    tags=["Bus AI"]
)

@router.post("/bus-recognition")
async def identify_bus(file: UploadFile = File(...)):
    # 1. 파일 확장자 검증
    if not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="이미지 파일만 업로드 가능합니다.")

    try:
        # 2. 파일 바이트 읽기
        image_bytes = await file.read()
        
        # 🔥 [안전장치] 파일 크기 체크 (예: 10MB 이상 거부)
        # Cloud Run 메모리 보호를 위해 너무 큰 파일은 미리 막는 것이 좋습니다.
        if len(image_bytes) > 10 * 1024 * 1024:
             raise HTTPException(status_code=413, detail="파일 크기가 너무 큽니다. (10MB 제한)")

        # 3. Vertex AI 엔드포인트 호출
        logger.info(f"Vertex AI 요청 시작: 파일명={file.filename}, 크기={len(image_bytes)} bytes")
        
        result = await request_vlm_prediction(
            image_bytes=image_bytes, 
            mime_type=file.content_type
        )
        
        logger.info(f"Vertex AI 응답 수신: {result}")

        # 4. 결과 파싱 (안전성 강화)
        # Vertex AI 응답 구조: {"predictions": ["결과 텍스트"]} 또는 {"predictions": [{"content": "..."}]}
        predictions = result.get("predictions")
        
        if not predictions:
            bus_number = "인식 실패 (응답 없음)"
        else:
            # 리스트의 첫 번째 요소를 가져옴
            first_pred = predictions[0]
            
            # 🔥 문자열인 경우와 딕셔너리인 경우 모두 대응
            if isinstance(first_pred, str):
                bus_number = first_pred
            elif isinstance(first_pred, dict):
                # 모델에 따라 'content', 'text', 'generated_text' 등 키가 다를 수 있음
                # 우선 전체를 문자열로 변환하거나 특정 키를 지정해야 함 (여기선 안전하게 값 추출 시도)
                bus_number = str(first_pred) 
            else:
                bus_number = str(first_pred)

        return {
            "status": "success",
            "bus_number": bus_number
        }
        
    except HTTPException as he:
        # 이미 정의된 HTTP 예외는 그대로 전달
        raise he
    except Exception as e:
        # 예측하지 못한 서버 내부 오류 로깅
        logger.error(f"버스 인식 중 오류 발생: {str(e)}")
        raise HTTPException(status_code=500, detail="버스 번호를 인식하는 중 문제가 발생했습니다.")