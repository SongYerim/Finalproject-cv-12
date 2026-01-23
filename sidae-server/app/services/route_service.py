import logging
from typing import List, Optional
from app.services.sk_api import SkTransitService
from app.services.path_parser import PathParser
from app.schemas.route_dto import RouteSegment

logger = logging.getLogger(__name__)

class RouteService:
    """
    경로 탐색 비즈니스 로직을 담당하는 파사드(Facade) 서비스
    - SkTransitService: TMap API 호출
    - PathParser: 응답 데이터 파싱 및 가공
    """
    def __init__(self, sk_api: SkTransitService, parser: PathParser):
        self.sk_api = sk_api
        self.parser = parser

    async def search_and_parse(
        self, 
        start_lat: float, 
        start_lng: float, 
        end_lat: float, 
        end_lng: float
    ) -> List[RouteSegment]:
        """
        대중교통 경로를 검색하고, 클라이언트가 사용하기 편한 형태로 파싱해 반환합니다.
        """
        # 1. TMAP API 호출
        logger.info(f"Route Search Request: {start_lat},{start_lng} -> {end_lat},{end_lng}")
        
        # sk_api.search_transit_route는 실패 시 HTTPException을 던짐 (기존 로직 유지)
        raw_data = await self.sk_api.search_transit_route(
            start_lat=start_lat, 
            start_lng=start_lng, 
            end_lat=end_lat, 
            end_lng=end_lng
        )

        # 2. 파싱 (하이브리드 로직 포함)
        # PathParser가 내부적으로 보행자 상세 경로를 위해 sk_api를 재사용함
        segments = await self.parser.parse(raw_data)
        
        if not segments:
            logger.warning("Parsed segments are empty.")
            return []

        logger.info(f"Successfully parsed {len(segments)} segments.")
        return segments
