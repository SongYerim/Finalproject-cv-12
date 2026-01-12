# app/main.py

from fastapi import FastAPI, Request
from app.routers.v1 import search, route

app = FastAPI(
    title="Sidae API",
    description="시각장애인을 위한 대중교통 도우미 '시대' 백엔드 서버",
    version="1.0.0"
)

# 🔥 [추가됨] 요청(Request) 로깅 미들웨어
@app.middleware("http")
async def log_requests(request: Request, call_next):
    # 1. 요청 정보 출력 (Method, URL, Query Params)
    print(f"\n📥 [REQUEST] {request.method} {request.url.path}")
    print(f"   Query Params: {request.query_params}")
    
    # 2. 다음 로직 실행
    response = await call_next(request)
    
    # 3. 응답 상태 코드 출력
    print(f"📤 [RESPONSE STATUS] {response.status_code}\n")
    return response

# 라우터 등록
app.include_router(search.router, prefix="/v1/search")
app.include_router(route.router, prefix="/v1/route")

@app.get("/")
def read_root():
    return {"message": "Sidae Server is Running!"}