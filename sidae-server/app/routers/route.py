from fastapi import APIRouter, Depends, Query, HTTPException
from typing import List

from app.dependencies import get_route_service
from app.services.route_service import RouteService
from app.schemas.route_dto import RouteSegment

router = APIRouter(tags=["Route"])

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
    service: RouteService = Depends(get_route_service)
):
    # RouteService를 통해 비즈니스 로직(검색+파싱) 수행
    segments = await service.search_and_parse(
        start_lat=start_lat, 
        start_lng=start_lng, 
        end_lat=end_lat, 
        end_lng=end_lng
    )

    if not segments:
        raise HTTPException(status_code=404, detail="경로 없음")
    
    return segments