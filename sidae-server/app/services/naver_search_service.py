import httpx
import logging
import re
from typing import Optional

logger = logging.getLogger(__name__)

class NaverSearchService:
    """
    네이버 검색 API (Local Search) 담당 서비스
    """
    SEARCH_LOCAL_URL = "https://openapi.naver.com/v1/search/local.json"

    # Constants
    KEY_ITEMS = "items"
    KEY_ROAD_ADDRESS = "roadAddress"
    KEY_ADDRESS = "address"
    
    PARAM_DISPLAY = 1
    PARAM_START = 1
    PARAM_SORT = "random"

    # Regex
    HTML_TAG_CLEANER = re.compile('<.*?>')

    def __init__(self, client: httpx.AsyncClient, search_client_id: str, search_client_secret: str):
        self.client = client
        self.headers = {
            "X-Naver-Client-Id": search_client_id,
            "X-Naver-Client-Secret": search_client_secret
        }

    async def search_keyword(self, query: str) -> Optional[str]:
        """
        [Keyword Search] 상호명/장소명(query)을 입력받아 가장 정확한 '도로명 주소'를 반환합니다.
        """
        params = {
            "query": query,
            "display": self.PARAM_DISPLAY,
            "start": self.PARAM_START,
            "sort": self.PARAM_SORT
        }

        try:
            response = await self.client.get(
                self.SEARCH_LOCAL_URL,
                headers=self.headers,
                params=params
            )
            response.raise_for_status()
            
            data = response.json()
            items = data.get(self.KEY_ITEMS, [])
            
            if not items:
                return None
            
            item = items[0]
            address = item.get(self.KEY_ROAD_ADDRESS) or item.get(self.KEY_ADDRESS)
            clean_address = self._remove_html_tags(address)
            
            return clean_address

        except httpx.HTTPError as e:
            logger.error(f"Naver Search API Error: {e} | Query: {query}")
            return None
        except Exception as e:
            logger.exception(f"Unexpected Error in Naver Search: {e} | Query: {query}")
            return None

    def _remove_html_tags(self, text: str) -> str:
        """문자열에서 HTML 태그 제거"""
        if not text:
            return ""
        return re.sub(self.HTML_TAG_CLEANER, '', text)
