import base64
import requests
import google.auth
import google.auth.transport.requests
from fastapi import HTTPException
import os
from dotenv import load_dotenv

load_dotenv()

# Google Cloud ADC(Application Default Credentials)를 사용하여 인증 토큰 획득
def get_access_token():
    creds, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    if not creds.valid:
        auth_req = google.auth.transport.requests.Request()
        creds.refresh(auth_req)
    return creds.token

async def request_vlm_prediction(image_bytes: bytes, mime_type: str, user_prompt: str):
    PROJECT_ID = os.getenv("PROJECT_ID")
    REGION = os.getenv("REGION")
    ENDPOINT_ID = os.getenv("ENDPOINT_ID")

    if not all([PROJECT_ID, REGION, ENDPOINT_ID]):
        raise HTTPException(status_code=500, detail="Server Configuration Error: Missing environment variables.")

    # rawPredict 엔드포인트 사용 (REST)
    url = f"https://{REGION}-aiplatform.googleapis.com/v1/projects/{PROJECT_ID}/locations/{REGION}/endpoints/{ENDPOINT_ID}:rawPredict"

    base64_image = base64.b64encode(image_bytes).decode("utf-8")

    # OpenAI Chat 포맷 구성 (vLLM 등 모델 서버 요구사항 충족)
    payload = {
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": user_prompt},
                    {
                        "type": "image_url", 
                        "image_url": {"url": f"data:{mime_type};base64,{base64_image}"}
                    }
                ]
            }
        ]
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