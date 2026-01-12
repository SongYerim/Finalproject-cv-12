import httpx
import re # HTML 태그 제거용
import logging
from typing import Optional, Tuple, Dict, Any
from fastapi import HTTPException, status
from app.core.config import settings

logger = logging.getLogger(__name__)

class NaverMapService:
    """
    Naver Cloud Platform Maps API 연동 서비스
    - Geocoding: 주소 -> 좌표 변환
    - Reverse Geocoding: 좌표 -> 주소 변환
    """
    
    # API 엔드포인트 상수 정의
    GEOCODE_URL = "https://maps.apigw.ntruss.com/map-geocode/v2/geocode"
    REVERSE_GEOCODE_URL = "https://maps.apigw.ntruss.com/map-reversegeocode/v2/gc"
    SEARCH_LOCAL_URL = "https://openapi.naver.com/v1/search/local.json"

    def __init__(self):
        # 1. Maps (Geocoding)용 헤더
        self.headers = {
            "X-NCP-APIGW-API-KEY-ID": settings.NCP_MAPS_CLIENT_ID,
            "X-NCP-APIGW-API-KEY": settings.NCP_MAPS_CLIENT_SECRET,
            "Accept": "application/json"
        }

        # 2. Search (Keyword)용 헤더
        self.search_headers = {
            "X-Naver-Client-Id": settings.NAVER_SEARCH_CLIENT_ID,
            "X-Naver-Client-Secret": settings.NAVER_SEARCH_CLIENT_SECRET
        }


    async def geocode(self, query: str) -> Optional[Tuple[float, float]]:
        """
        [Geocoding] 주소를 입력받아 위도(lat), 경도(lng) 좌표를 반환합니다.
        
        Args:
            query (str): 검색할 주소 (예: "분당구 불정로 6")
            
        Returns:
            Optional[Tuple[float, float]]: (위도, 경도) 튜플 또는 None (검색 결과 없음)
        """
        params = {"query": query}

        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(
                    self.GEOCODE_URL, 
                    headers=self.headers, 
                    params=params
                )
                response.raise_for_status() # 200 OK가 아니면 예외 발생
                
                data = response.json()
                
                # 검색 결과(addresses)가 존재하는지 확인
                if not data.get("addresses"):
                    return None
                
                # 첫 번째 검색 결과의 좌표 추출
                # Naver API 반환값: x=경도(lng), y=위도(lat)
                first_result = data["addresses"][0]
                lng = float(first_result["x"])
                lat = float(first_result["y"])
                
                return (lat, lng)

            except httpx.HTTPStatusError as e:
                # [3] print 대신 logger.error 사용
                # error 레벨: 심각한 문제일 때 사용합니다.
                logger.error(f"Naver Geocoding API Error: {e} | Query: {query}")
                
                # 필요하다면 사용자가 보낸 데이터(query)도 같이 기록해두면 디버깅에 좋습니다.
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail="Naver Maps API 호출 중 오류가 발생했습니다."
                )

    async def reverse_geocode(self, lat: float, lng: float) -> Optional[str]:
        """
        [Reverse Geocoding] 좌표(위도, 경도)를 입력받아 도로명 주소(또는 지번 주소)를 반환합니다.
        
        Args:
            lat (float): 위도
            lng (float): 경도
            
        Returns:
            Optional[str]: 변환된 전체 주소 문자열 또는 None
        """
        # API 요청 파라미터: coords=경도,위도 (순서 주의!)
        params = {
            "coords": f"{lng},{lat}",
            "output": "json",
            "orders": "roadaddr,addr" # 도로명 주소 우선, 없으면 지번 주소
        }

        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(
                    self.REVERSE_GEOCODE_URL, 
                    headers=self.headers, 
                    params=params
                )
                response.raise_for_status()
                
                data = response.json()
                results = data.get("results", [])
                
                if not results:
                    return None
                
                # 결과 조합: region(지역명) + land(상세주소)
                # 'orders' 순서대로 결과가 배열에 담김 (0번 인덱스가 우선순위 높음)
                best_result = results[0]
                
                region = best_result.get("region", {})
                land = best_result.get("land", {})
                
                # 지역명 조합 (예: 경기도 성남시 분당구)
                area1 = region.get("area1", {}).get("name", "")
                area2 = region.get("area2", {}).get("name", "")
                area3 = region.get("area3", {}).get("name", "")
                
                # 상세 주소 조합 (도로명 or 지번)
                if best_result["name"] == "roadaddr":
                    road_name = land.get("name", "")
                    road_number = land.get("number1", "")
                    detail = f"{road_name} {road_number}".strip()
                else: # addr (지번)
                    number1 = land.get("number1", "")
                    number2 = land.get("number2", "")
                    detail = f"{number1}-{number2}" if number2 else number1
                
                full_address = f"{area1} {area2} {area3} {detail}".strip()
                return full_address

            except httpx.HTTPStatusError as e:
                logger.error(f"Naver Reverse Geocoding API Error: {e} | Coords: {lat}, {lng}")
                
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail="Naver Maps API 호출 중 오류가 발생했습니다."
                )

    async def search_keyword(self, query: str) -> Optional[str]:
        """
        [Keyword Search] 상호명/장소명(query)을 입력받아 가장 정확한 '도로명 주소'를 반환합니다.
        예: "홍대 스타벅스" -> "서울특별시 마포구 양화로 165"
        """
        params = {
            "query": query,
            "display": 1,  # 가장 정확한 결과 1개만
            "start": 1,
            "sort": "random" # 정확도순 정렬
        }

        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(
                    self.SEARCH_LOCAL_URL,
                    headers=self.search_headers,
                    params=params
                )
                response.raise_for_status()
                
                data = response.json()
                items = data.get("items", [])
                
                if not items:
                    return None
                
                # 결과에서 가장 적절한 주소 추출
                item = items[0]
                # 도로명 주소가 있으면 우선 사용, 없으면 지번 주소 사용
                address = item.get("roadAddress") or item.get("address")
                
                # HTML 태그 제거 (가끔 결과에 <b>스타벅스</b> 처럼 태그가 섞여 옴)
                clean_address = self._remove_html_tags(address)
                
                return clean_address

            except Exception as e:
                print(f"Naver Search API Error: {e}")
                # 검색 실패 시 None 반환 (호출부에서 처리)
                return None

    def _remove_html_tags(self, text: str) -> str:
        """문자열에서 HTML 태그 제거"""
        if not text:
            return ""
        clean = re.compile('<.*?>')
        return re.sub(clean, '', text)