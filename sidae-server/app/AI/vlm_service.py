import base64
import requests
import google.auth
import google.auth.transport.requests
from fastapi import HTTPException

# 1. 인증 토큰 생성 (Cloud Run 서비스 계정 권한 이용)
def get_access_token():
    creds, _ = google.auth.default()
    auth_req = google.auth.transport.requests.Request()
    creds.refresh(auth_req)
    return creds.token

async def request_vlm_prediction(image_bytes: bytes, mime_type: str):
    # 프로젝트 고정 정보 활용 
    PROJECT_ID = "YOUR_PROJECT_ID" 
    REGION = "asia-northeast3" 
    ENDPOINT_ID = "YOUR_ENDPOINT_ID" # 위 1단계에서 복사한 ID

    # 2. 주소 설정
    url = f"https://{REGION}-aiplatform.googleapis.com/v1/projects/{PROJECT_ID}/locations/{REGION}/endpoints/{ENDPOINT_ID}:predict"

    # 3. Base64 인코딩
    base64_image = base64.b64encode(image_bytes).decode("utf-8")

    # 4. Qwen-VLM 모델 전용 페이로드 구성 [cite: 95, 118]
    # 버스 번호 인식을 위한 프롬프트 포함
    payload = {
        "instances": [
            {
                "prompt": "이 사진에서 버스 번호판이나 노선 번호를 찾아서 숫자만 알려줘.",
                "image": {"bytesBase64Encoded": base64_image}
            }
        ]
    }

    headers = {
        "Authorization": f"Bearer {get_access_token()}",
        "Content-Type": "application/json"
    }

    # 5. API 호출
    response = requests.post(url, json=payload, headers=headers)

    if response.status_code != 200:
        raise HTTPException(status_code=response.status_code, detail=response.text)

    return response.json()