import httpx
import logging
from typing import Optional, Tuple
from app.services.naver_common import NaverApiError

logger = logging.getLogger(__name__)

class NaverGeoService:
    """
    네이버 Maps API (Geocoding/Reverse Geocoding) 담당 서비스
    """
    GEOCODE_URL = "https://maps.apigw.ntruss.com/map-geocode/v2/geocode"
    REVERSE_GEOCODE_URL = "https://maps.apigw.ntruss.com/map-reversegeocode/v2/gc"

    # API Constants
    KEY_ADDRESSES = "addresses"
    KEY_RESULTS = "results"
    KEY_X = "x"
    KEY_Y = "y"
    KEY_REGION = "region"
    KEY_LAND = "land"
    KEY_AREA1 = "area1"
    KEY_AREA2 = "area2"
    KEY_AREA3 = "area3"
    KEY_NAME = "name"
    KEY_NUMBER1 = "number1"
    KEY_NUMBER2 = "number2"
    VAL_ROADADDR = "roadaddr"

    def __init__(self, client: httpx.AsyncClient, ncp_client_id: str, ncp_client_secret: str):
        self.client = client
        self.headers = {
            "X-NCP-APIGW-API-KEY-ID": ncp_client_id,
            "X-NCP-APIGW-API-KEY": ncp_client_secret,
            "Accept": "application/json"
        }

    async def geocode(self, query: str) -> Optional[Tuple[float, float]]:
        """
        [Geocoding] 주소를 입력받아 위도(lat), 경도(lng) 좌표를 반환합니다.
        """
        params = {"query": query}

        try:
            response = await self.client.get(
                self.GEOCODE_URL, 
                headers=self.headers, 
                params=params
            )
            response.raise_for_status()
            
            data = response.json()
            
            if not data.get(self.KEY_ADDRESSES):
                return None
            
            first_result = data[self.KEY_ADDRESSES][0]
            lng = float(first_result[self.KEY_X])
            lat = float(first_result[self.KEY_Y])
            
            return (lat, lng)

        except httpx.HTTPStatusError as e:
            logger.error(f"Naver Geocoding API Error: {e} | Query: {query}")
            raise NaverApiError(f"Naver Maps API Error: {e}") from e
        except httpx.RequestError as e:
             logger.error(f"Naver Geocoding Connection Error: {e} | Query: {query}")
             raise NaverApiError(f"Naver Maps Connection Error: {e}") from e

    async def reverse_geocode(self, lat: float, lng: float) -> Optional[str]:
        """
        [Reverse Geocoding] 좌표(위도, 경도)를 입력받아 도로명 주소(또는 지번 주소)를 반환합니다.
        """
        params = {
            "coords": f"{lng},{lat}",
            "output": "json",
            "orders": "roadaddr,addr"
        }

        try:
            response = await self.client.get(
                self.REVERSE_GEOCODE_URL, 
                headers=self.headers, 
                params=params
            )
            response.raise_for_status()
            
            data = response.json()
            results = data.get(self.KEY_RESULTS, [])
            
            if not results:
                return None
            
            return self._parse_address_from_results(results[0])

        except httpx.HTTPStatusError as e:
            logger.error(f"Naver Reverse Geocoding API Error: {e} | Coords: {lat}, {lng}")
            raise NaverApiError(f"Naver Maps API Error: {e}") from e
        except httpx.RequestError as e:
            logger.error(f"Naver Reverse Geocoding Connection Error: {e}")
            raise NaverApiError(f"Naver Maps Connection Error: {e}") from e

    def _parse_address_from_results(self, best_result: dict) -> str:
        """네이버 Reverse Geocoding 응답에서 주소를 파싱합니다."""
        region = best_result.get(self.KEY_REGION, {})
        land = best_result.get(self.KEY_LAND, {})
        
        area1 = region.get(self.KEY_AREA1, {}).get(self.KEY_NAME, "")
        area2 = region.get(self.KEY_AREA2, {}).get(self.KEY_NAME, "")
        area3 = region.get(self.KEY_AREA3, {}).get(self.KEY_NAME, "")
        
        if best_result.get(self.KEY_NAME) == self.VAL_ROADADDR:
            road_name = land.get(self.KEY_NAME, "")
            road_number = land.get(self.KEY_NUMBER1, "")
            detail = f"{road_name} {road_number}".strip()
        else:
            number1 = land.get(self.KEY_NUMBER1, "")
            number2 = land.get(self.KEY_NUMBER2, "")
            detail = f"{number1}-{number2}" if number2 else number1
        
        return f"{area1} {area2} {area3} {detail}".strip()
