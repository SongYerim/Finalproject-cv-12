# app/routers/v1/route.py

import json
from fastapi.encoders import jsonable_encoder # Pydantic 모델을 dict로 변환용
from typing import List
from fastapi import APIRouter, Depends, Query, HTTPException, status
from app.services.sk_api import SkTransitService
from app.services.path_parser import PathParser
from app.schemas.common import RouteSegment

router = APIRouter(tags=["Route"])

def get_sk_transit_service() -> SkTransitService:
    return SkTransitService()

def get_path_parser(sk_service: SkTransitService = Depends(get_sk_transit_service)) -> PathParser:
    return PathParser(sk_service=sk_service)

@router.get(
    "/search",
    response_model=List[RouteSegment],
    summary="대중교통 최단 경로 탐색"
)
async def search_route(
    start_lat: float = Query(...),
    start_lng: float = Query(...),
    end_lat: float = Query(...),
    end_lng: float = Query(...),
    sk_service: SkTransitService = Depends(get_sk_transit_service),
    parser: PathParser = Depends(get_path_parser)
):
    # 1. TMAP API 호출
    raw_data = await sk_service.search_transit_route(
        start_lat=start_lat, start_lng=start_lng, end_lat=end_lat, end_lng=end_lng
    )

    # 2. 파싱 (하이브리드 로직 포함)
    segments = await parser.parse(raw_data)

    if not segments:
        raise HTTPException(status_code=404, detail="경로 없음")
    
    # 🔥 [추가됨] 최종 응답 데이터 로그 출력 (JSON Pretty Print)
    print("📦 [FINAL RESPONSE DATA]")
    # Pydantic 모델 리스트를 JSON 형태로 변환
    json_compatible_item_data = jsonable_encoder(segments)
    # 들여쓰기(indent=2)를 적용해 예쁘게 출력
    print(json.dumps(json_compatible_item_data, indent=2, ensure_ascii=False))
    print("--------------------------------------------------")

    return segments