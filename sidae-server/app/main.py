import logging
from contextlib import asynccontextmanager
import httpx
from fastapi import FastAPI, Request
from app.routers import route, search, bus_ai, bus

@asynccontextmanager
async def lifespan(app: FastAPI):
    # HttpClient 생성 & app.state에 저장
    app.state.http_client = httpx.AsyncClient()
    yield
    # HttpClient 리소스 해제
    await app.state.http_client.aclose()

app = FastAPI(
    title="시대(Sidae) API 서버",
    description="시각장애인을 위한 대중교통 도우미 '시대' 백엔드 서버",
    version="1.0.0",
    lifespan=lifespan
)

# 요청(Request) 로깅 미들웨어
logger = logging.getLogger("uvicorn") # 로거 이름을 uvicorn으로 맞추면 Cloud Run 로그에서 보기 편합니다.

@app.middleware("http")
async def log_requests(request: Request, call_next):
    # 1. 요청 정보 출력 (Method, URL, Query Params)
    logger.info(f"[REQUEST] {request.method} {request.url.path} | Query: {request.query_params}")
    
    # 2. 다음 로직 실행
    response = await call_next(request)
    
    # 3. 응답 상태 코드 출력
    logger.info(f"[RESPONSE STATUS] {response.status_code}")
    return response

# 라우터 등록 (Router Registration)
app.include_router(search.router, prefix="/search")
app.include_router(route.router, prefix="/route")
app.include_router(bus.router, prefix="/bus")

@app.get("/")
def read_root():
    return {"message": "Sidae Server is Running!"}