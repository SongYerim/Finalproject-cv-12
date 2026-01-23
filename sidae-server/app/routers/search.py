from fastapi import APIRouter, Depends, Query, HTTPException, status, Request
from app.dependencies import get_naver_place_service
from app.services.naver_place_service import NaverPlaceService
from app.services.naver_common import NaverApiError
from app.schemas.search_dto import LocationResponse

router = APIRouter(tags=["Search"])

@router.get(
    "/place",
    response_model=LocationResponse,
    summary="네이버 검색 + Geocoding (최적 장소 1개)",
    description="검색어를 받아 네이버 검색 API로 장소를 찾고, Geocoding으로 좌표를 변환하여 반환합니다."
)
async def search_place(
    query: str = Query(..., min_length=1, description="검색할 장소명"),
    service: NaverPlaceService = Depends(get_naver_place_service)
):
    try:
        # 서비스 레이어로 비즈니스 로직(검색 전략) 이관
        result = await service.get_optimized_coordinates(query)

        if not result:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"'{query}'에 대한 위치를 찾을 수 없습니다."
            )
            
        # DTO -> Response 변환
        return LocationResponse(
            name=result.name,
            address=result.address,
            latitude=result.lat,
            longitude=result.lng
        )
        
    except NaverApiError as e:
        # Service 레벨의 에러를 HTTP 502로 변환
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Naver Maps API 호출 중 오류가 발생했습니다."
        )