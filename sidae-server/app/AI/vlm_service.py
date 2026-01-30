import base64
import requests
import google.auth
import google.auth.transport.requests
from fastapi import HTTPException
import os
from dotenv import load_dotenv
from PIL import Image
import io

def resize_image_smart(
    image_bytes: bytes, 
    min_pixels: int = 256 * 256,
    max_pixels: int = 512 * 512
) -> bytes:
    """
    이미지 비율을 유지하면서:
    1. 총 픽셀 수가 min_pixels보다 작으면 -> 확대 (Upscaling)
    2. 총 픽셀 수가 max_pixels보다 크면 -> 축소 (Downscaling)
    3. 그 사이라면 -> 원본 유지
    """
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
            
            image = image.resize((new_width, new_height), Image.Resampling.LANCZOS)
        
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
        return image_bytes

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
    optimized_image_bytes = resize_image_smart(image_bytes, min_pixels=147456, max_pixels=262144)
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

        response = requests.post(url, json=payload, headers=headers)

        if response.status_code != 200:
            raise HTTPException(status_code=response.status_code, detail=f"Vertex AI API Error: {response.text}")

        return response.json()

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Request Error: {str(e)}")