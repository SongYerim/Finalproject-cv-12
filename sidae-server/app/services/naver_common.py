from dataclasses import dataclass

class NaverApiError(Exception):
    """Naver API 관련 커스텀 예외"""
    pass

@dataclass(frozen=True)
class LocationDTO:
    name: str
    address: str
    lat: float
    lng: float
