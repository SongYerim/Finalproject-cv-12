import base64
import requests
import google.auth
import google.auth.transport.requests
from fastapi import HTTPException
import os
from dotenv import load_dotenv
from PIL import Image
import io
import time
import cv2
import numpy as np
import logging

# 로거 설정
logger = logging.getLogger("uvicorn")

def resize_image_smart(
    image_bytes: bytes, 
    min_pixels: int = 256 * 256,
    max_pixels: int = 512 * 512
) -> bytes:
    """
    OpenCV를 사용한 고속 리사이징
    """
    try:
        # 1. Bytes -> Numpy Array 변환 (디코딩)
        # np.frombuffer는 데이터 복사 없이 뷰만 생성하므로 매우 빠름
        nparr = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if img is None:
            return image_bytes

        h, w = img.shape[:2]
        current_pixels = w * h
        
        # 2. 리사이징 필요 여부 계산
        target_pixels = None
        if current_pixels < min_pixels:
            target_pixels = min_pixels
        elif current_pixels > max_pixels:
            target_pixels = max_pixels
            
        # 3. 리사이징 수행
        if target_pixels:
            scale_factor = (target_pixels / current_pixels) ** 0.5
            new_width = int(w * scale_factor)
            new_height = int(h * scale_factor)
            
            # INTER_LINEAR: 빠르고 화질 준수 (기본값)
            # INTER_AREA: 축소할 때 화질 좋음 (약간 더 느림)
            # 여기서는 속도가 중요하므로 INTER_LINEAR 추천
            img = cv2.resize(img, (new_width, new_height), interpolation=cv2.INTER_AREA)

        # 4. 이미지 인코딩 (다시 Bytes로)
        # quality: 85 (Pillow와 동일하게 설정)
        encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), 95]
        success, encoded_img = cv2.imencode(".jpg", img, encode_param)
        
        if success:
            return encoded_img.tobytes()
        else:
            return image_bytes

    except Exception as e:
        print(f"OpenCV resize failed: {e}")
        return image_bytes

"""def resize_image_smart(
    image_bytes: bytes, 
    min_pixels: int = 256 * 256,
    max_pixels: int = 512 * 512
) -> bytes:
    
    #이미지 비율을 유지하면서:
    #1. 총 픽셀 수가 min_pixels보다 작으면 -> 확대 (Upscaling)
    #2. 총 픽셀 수가 max_pixels보다 크면 -> 축소 (Downscaling)
    #3. 그 사이라면 -> 원본 유지
    
    try:
        image = Image.open(io.BytesIO(image_bytes))
        
        # 현재 픽셀 수 계산
        current_pixels = image.width * image.height
        
        # 변경이 필요한지 확인
        target_pixels = None
        
        if current_pixels < min_pixels:
            target_pixels = min_pixels
        elif current_pixels > max_pixels:
            target_pixels = max_pixels
            
        # 리사이징 수행 (변경이 필요한 경우에만)
        if target_pixels:
            # 스케일 비율 계산 (루트 씌워서 가로/세로 비율 산출)
            scale_factor = (target_pixels / current_pixels) ** 0.5
            new_width = int(image.width * scale_factor)
            new_height = int(image.height * scale_factor)
            
            image = image.resize((new_width, new_height), Image.Resampling.BILINEAR)
        
        # 다시 bytes로 변환
        buffer = io.BytesIO()
        # 원본 포맷 유지 (없으면 JPEG)
        fmt = image.format if image.format else 'JPEG'
        
        # JPEG일 경우 품질 최적화 (용량 절약)
        if fmt == 'JPEG':
            image.save(buffer, format=fmt, quality=85)
        else:
            image.save(buffer, format=fmt)
            
        return buffer.getvalue()

    except Exception as e:
        # 이미지 처리 중 에러 발생 시 원본 반환 (안전 장치)
        print(f"Image resize failed: {e}")
        return image_bytes"""

load_dotenv()

# Google Cloud ADC(Application Default Credentials)를 사용하여 인증 토큰 획득
def get_access_token():
    creds, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    if not creds.valid:
        auth_req = google.auth.transport.requests.Request()
        creds.refresh(auth_req)
    return creds.token

async def request_vlm_prediction(image_bytes: bytes, mime_type: str, user_prompt: str, system_prompt: str="", max_tokens= int):
    PROJECT_ID = os.getenv("PROJECT_ID")
    REGION = os.getenv("REGION")
    ENDPOINT_ID = os.getenv("ENDPOINT_ID")
    if not all([PROJECT_ID, REGION, ENDPOINT_ID]):
        raise HTTPException(status_code=500, detail="Server Configuration Error: Missing environment variables.")

    # rawPredict 엔드포인트 사용 (REST)
    url = f"https://{REGION}-aiplatform.googleapis.com/v1/projects/{PROJECT_ID}/locations/{REGION}/endpoints/{ENDPOINT_ID}:rawPredict"
    resize_s = time.time()
    optimized_image_bytes = resize_image_smart(image_bytes, min_pixels=147456, max_pixels=262144)
    resize_e = time.time()
    base64_image = base64.b64encode(optimized_image_bytes).decode("utf-8")
    messages = []

    if system_prompt:
        messages.append({
            "role": "system",
            "content": system_prompt
        })

    user_message = {
        "role": "user",
        "content": [
            {
                "type": "text", 
                "text": user_prompt
            },
            {
                "type": "image_url",
                "image_url": {
                    "url": f"data:{mime_type};base64,{base64_image}"
                }
            }
        ]
    }
    messages.append(user_message)


    payload = {
        "messages": messages,
        "max_tokens": max_tokens
    }
    
    try:
        # 토큰 자동 획득
        token = get_access_token()
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "X-Goog-User-Project": PROJECT_ID 
        }
        model_s = time.time()
        response = requests.post(url, json=payload, headers=headers)
        model_e = time.time()
        resize_time = (resize_e - resize_s) * 1000
        model_time = (model_e - model_s) * 1000
        if response.status_code != 200:
            raise HTTPException(status_code=response.status_code, detail=f"Vertex AI API Error: {response.text}")

        return [response.json(), resize_time, model_time]

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Request Error: {str(e)}")


async def request_vlm_prediction_with_tools(
    image_bytes: bytes,
    mime_type: str,
    user_prompt: str,
    system_prompt: str = "",
    tools: list = None,
    context: dict = None,
    max_tokens: int = 300,
    max_tool_calls: int = 3
):
    """
    Tool calling을 지원하는 VLM 호출 (최적화 버전).
    
    흐름:
    1. 첫 호출: 텍스트만 + tools (이미지 X) → Tool 필요 여부 체크
    2-A. Tool 필요 → Tool 실행 → 두 번째 호출: 텍스트 + tool 결과 (이미지 X)
    2-B. Tool 불필요 → 두 번째 호출: 텍스트 + 이미지 (직접 답변)
    
    Args:
        image_bytes: 이미지 바이트
        mime_type: 이미지 MIME 타입
        user_prompt: 사용자 질문
        system_prompt: 시스템 프롬프트
        tools: Tool 정의 목록
        context: 앱에서 전달받은 컨텍스트
        max_tokens: 최대 토큰 수
        max_tool_calls: 최대 tool 호출 횟수 (무한 루프 방지)
    
    Returns:
        [최종 응답 텍스트, resize_time, model_time]
    """
    from .tools import execute_tool
    import json
    
    PROJECT_ID = os.getenv("PROJECT_ID")
    REGION = os.getenv("REGION")
    ENDPOINT_ID = os.getenv("ENDPOINT_ID")
    if not all([PROJECT_ID, REGION, ENDPOINT_ID]):
        raise HTTPException(status_code=500, detail="Server Configuration Error: Missing environment variables.")

    url = f"https://{REGION}-aiplatform.googleapis.com/v1/projects/{PROJECT_ID}/locations/{REGION}/endpoints/{ENDPOINT_ID}:rawPredict"
    
    # 이미지 리사이징 (나중에 필요할 때 사용)
    resize_s = time.time()
    optimized_image_bytes = resize_image_smart(image_bytes, min_pixels=147456, max_pixels=262144)
    resize_e = time.time()
    resize_time = (resize_e - resize_s) * 1000
    
    base64_image = base64.b64encode(optimized_image_bytes).decode("utf-8")
    
    # 메시지 초기화 (첫 호출: 텍스트만, 이미지 X)
    messages = []
    if system_prompt:
        messages.append({"role": "system", "content": system_prompt})
    
    # 첫 호출은 텍스트만 (이미지 없음)
    messages.append({
        "role": "user",
        "content": user_prompt  # 텍스트만
    })
    
    total_model_time = 0
    tool_was_used = False  # Tool 사용 여부 추적
    
    # Tool calling 루프
    for i in range(max_tool_calls):
        payload = {
            "messages": messages,
            "max_tokens": max_tokens
        }
        # 첫 번째 호출에서만 tools 전달
        if tools and i == 0:
            payload["tools"] = tools
        
        try:
            token = get_access_token()
            headers = {
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
                "X-Goog-User-Project": PROJECT_ID
            }
            
            model_s = time.time()
            response = requests.post(url, json=payload, headers=headers)
            model_e = time.time()
            total_model_time += (model_e - model_s) * 1000
            
            if response.status_code != 200:
                raise HTTPException(status_code=response.status_code, detail=f"Vertex AI API Error: {response.text}")
            
            result = response.json()
            choices = result.get("choices", [])
            
            if not choices:
                return [{"choices": [{"message": {"content": "응답을 생성할 수 없습니다."}}]}, resize_time, total_model_time]
            
            choice = choices[0]
            finish_reason = choice.get("finish_reason", "")
            message = choice.get("message", {})
            
            # Tool 호출인 경우
            tool_calls = message.get("tool_calls", [])
            if tool_calls or finish_reason == "tool_calls":
                tool_was_used = True
                logger.info(f"Tool 호출 감지: {len(tool_calls)}개 도구")
                # Assistant 메시지 추가 (tool_calls 포함)
                messages.append(message)
                
                # 각 Tool 실행 및 결과 추가
                for tool_call in tool_calls:
                    func = tool_call.get("function", {})
                    tool_name = func.get("name", "")
                    tool_call_id = tool_call.get("id", "")
                    
                    logger.info(f"Tool 실행: {tool_name}")
                    tool_result = execute_tool(tool_name, context or {})
                    logger.info(f"Tool 결과: {tool_result}")
                    
                    # Tool 결과 메시지 추가
                    messages.append({
                        "role": "tool",
                        "tool_call_id": tool_call_id,
                        "content": json.dumps(tool_result, ensure_ascii=False)
                    })
                # 다음 루프에서 모델이 결과를 해석하도록 계속 진행 (이미지 없이)
                continue
            
            # 첫 호출에서 Tool 사용 안 함 → 이미지 포함하여 재호출
            if i == 0 and not tool_was_used:
                logger.info("Tool 미사용 → 이미지 포함하여 재호출")
                # 기존 user 메시지를 이미지 포함 버전으로 교체
                messages[-1] = {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": user_prompt},
                        {"type": "image_url", "image_url": {"url": f"data:{mime_type};base64,{base64_image}"}}
                    ]
                }
                # tools 없이 다시 호출
                continue
            
            # 최종 응답인 경우
            content = message.get("content", "")
            if content or finish_reason == "stop":
                logger.info(f"최종 응답: {content[:100]}...")
                return [{"choices": [{"message": {"content": content}}]}, resize_time, total_model_time]
            
            # 예상치 못한 상황
            return [{"choices": [{"message": {"content": content or "응답을 생성할 수 없습니다."}}]}, resize_time, total_model_time]
                
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Tool calling error: {str(e)}")
    
    # 최대 루프 도달
    return [{"choices": [{"message": {"content": "응답을 생성할 수 없습니다."}}]}, resize_time, total_model_time]