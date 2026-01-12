from enum import Enum
from pydantic import BaseModel, Field
from typing import List, Optional, Any

class LocationResponse(BaseModel):
    name: str = Field(..., description="장소명")
    address: str = Field("", description="주소")
    latitude: float = Field(..., description="위도")
    longitude: float = Field(..., description="경도")

class MoveType(str, Enum):
    WALK = "WALK"
    BUS = "BUS"
    SUBWAY = "SUBWAY"

class StationInfo(BaseModel):
    index: int
    name: str
    lat: float
    lng: float

# ✨ [수정] RouteStep에 path 필드 추가
class RouteStep(BaseModel):
    description: str = Field(..., description="안내 문구")
    lat: float = Field(..., description="지점 위도")
    lng: float = Field(..., description="지점 경도")
    turn_type: int = Field(0, alias="turnType")
    facility_type: str = Field("", alias="facilityType")
    
    road_type: int = Field(0, alias="roadType", description="보행자 도로 타입 (21~24)")
    time: int = Field(0, alias="time", description="구간별 시간")
    distance: int = Field(0, alias="distance", description="구간별 거리")
    path: List[List[float]] = Field(default=[], description="이 구간의 경로선 좌표 [[lat, lng], ...]")

    class Config:
        populate_by_name = True

class RouteSegment(BaseModel):
    segment_index: int
    move_type: MoveType
    description: str
    step_description: List[str] = []
    steps: List[RouteStep] = []
    transport_name: Optional[str] = None
    start_station: Optional[str] = None
    end_station: Optional[str] = None
    path_coordinates: List[List[float]] = []
    distance: int = 0
    duration: int = 0
    stations: List[StationInfo] = []