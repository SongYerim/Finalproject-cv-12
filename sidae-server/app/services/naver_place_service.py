import logging
from typing import Optional
from app.services.naver_common import LocationDTO
from app.services.naver_geo_service import NaverGeoService
from app.services.naver_search_service import NaverSearchService

logger = logging.getLogger(__name__)

class NaverPlaceService:
    """
    위치 정보 오케스트레이션 서비스 (Facade)
    GeoService와 SearchService를 조합하여 최적의 위치 정보를 찾습니다.
    """
    def __init__(self, geo_service: NaverGeoService, search_service: NaverSearchService):
        self.geo_service = geo_service
        self.search_service = search_service

    async def get_optimized_coordinates(self, query: str) -> Optional[LocationDTO]:
        """
        [Search Orchestration]
        1. Geocoding 시도 (정확한 주소인 경우)
        2. 실패 시 Keyword Search -> Geocoding 재시도
        """
        # 1. Geocoding 우선 시도
        found_address = query
        coordinates = await self.geo_service.geocode(query)

        # 2. 실패 시 Keyword Search 시도
        if not coordinates:
            logger.info(f"🔍 [Naver Search] '{query}' 키워드 검색 시도...")
            found_address = await self.search_service.search_keyword(query)
            
            if found_address:
                logger.info(f"✅ 장소 발견: {found_address}")
                coordinates = await self.geo_service.geocode(found_address)

        # 3. 최종 결과 반환
        if coordinates and found_address: # found_address 체크 추가 (None일 경우 방지)
            return LocationDTO(
                name=query,
                address=found_address,
                lat=coordinates[0],
                lng=coordinates[1]
            )

        return None
