# app/schemas/bus.py
from pydantic import BaseModel, Field
from typing import Optional

class BusArrivalResponse(BaseModel):
    bus_number: str = Field(..., description="버스 번호 (예: 1711)")
    station_name: str = Field(..., description="정류장 이름")
    status_msg: str = Field(..., description="도착 예정 시간 또는 상태 (예: 3분20초후)")
    plate_no: str = Field(..., description="차량 번호")
    veh_id: str = Field(..., description="버스 고유 ID (실시간 위치 조회용)")
    station_seq: str = Field(..., description="정류장 순번")

class BusLocationResponse(BaseModel):
    veh_id: str = Field(..., description="버스 고유 ID")
    tmX: float = Field(..., description="X 좌표 (경도)")
    tmY: float = Field(..., description="Y 좌표 (위도)")
    data_tm: Optional[str] = Field(None, description="데이터 수집 시간")