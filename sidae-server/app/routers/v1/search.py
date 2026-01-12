# app/routers/v1/search.py

from fastapi import APIRouter, Depends, Query, HTTPException, status
from app.services.naver_api import NaverMapService
from app.schemas.common import LocationResponse

router = APIRouter(tags=["Search"])

def get_naver_map_service() -> NaverMapService:
    return NaverMapService()

@router.get(
    "/place",
    response_model=LocationResponse,
    summary="네이버 검색 + Geocoding (최적 장소 1개)",
    description="검색어를 받아 네이버 검색 API로 장소를 찾고, Geocoding으로 좌표를 변환하여 반환합니다."
)
async def search_place(
    query: str = Query(..., min_length=1, description="검색할 장소명"),
    service: NaverMapService = Depends(get_naver_map_service)
):
    # 1단계: 검색어가 '정확한 주소'일 수도 있으니 바로 좌표 변환 시도
    coordinates = await service.geocode(query)
    final_name = query
    address = query

    # 2단계: 주소가 아니어서 실패했다면 -> '네이버 검색 API'로 장소 검색
    if not coordinates:
        print(f"🔍 [Naver Search] '{query}' 키워드 검색 시도...")
        
        # 네이버 지역 검색 API 호출 (가장 관련성 높은 주소 1개 가져옴)
        found_address = await service.search_keyword(query)
        
        if found_address:
            print(f"✅ 장소 발견: {found_address}")
            final_name = query
            address = found_address
            # 찾은 주소로 다시 좌표 변환 (Geocoding API)
            coordinates = await service.geocode(found_address)

    # 3단계: 최종 실패 처리
    if not coordinates:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"'{query}'에 대한 위치를 찾을 수 없습니다."
        )

    lat, lng = coordinates
    
    # 최적 장소 1개 반환
    return LocationResponse(
        name=final_name,
        address=address,
        latitude=lat,
        longitude=lng
    )