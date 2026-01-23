import httpx
from fastapi import Request, Depends
from app.core.config import settings
from app.services.naver_geo_service import NaverGeoService
from app.services.naver_search_service import NaverSearchService
from app.services.naver_place_service import NaverPlaceService
from app.services.sk_api import SkTransitService
from app.services.path_parser import PathParser
from app.services.route_service import RouteService

def get_http_client(request: Request) -> httpx.AsyncClient:
    return request.app.state.http_client

def get_naver_geo_service(client: httpx.AsyncClient = Depends(get_http_client)) -> NaverGeoService:
    return NaverGeoService(
        client=client,
        ncp_client_id=settings.NCP_MAPS_CLIENT_ID,
        ncp_client_secret=settings.NCP_MAPS_CLIENT_SECRET
    )

def get_naver_search_service(client: httpx.AsyncClient = Depends(get_http_client)) -> NaverSearchService:
    return NaverSearchService(
        client=client,
        search_client_id=settings.NAVER_SEARCH_CLIENT_ID,
        search_client_secret=settings.NAVER_SEARCH_CLIENT_SECRET
    )

def get_naver_place_service(
    geo_service: NaverGeoService = Depends(get_naver_geo_service),
    search_service: NaverSearchService = Depends(get_naver_search_service)
) -> NaverPlaceService:
    return NaverPlaceService(
        geo_service=geo_service,
        search_service=search_service
    )

def get_sk_transit_service(client: httpx.AsyncClient = Depends(get_http_client)) -> SkTransitService:
    return SkTransitService(client=client, api_key=settings.SK_API_KEY)

def get_path_parser(sk_service: SkTransitService = Depends(get_sk_transit_service)) -> PathParser:
    return PathParser(sk_service=sk_service)

def get_route_service(
    sk_service: SkTransitService = Depends(get_sk_transit_service),
    parser: PathParser = Depends(get_path_parser)
) -> RouteService:
    return RouteService(sk_api=sk_service, parser=parser)
