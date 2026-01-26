# app/routers/bus.py
from fastapi import APIRouter, Depends, HTTPException, Request, Query
from app.services.bus_api import BusTransitService
from app.schemas.bus_info import BusArrivalResponse, BusLocationResponse

router = APIRouter(tags=["Bus Info"])

# 📌 의존성 주입 함수: main.py의 app.state.http_client를 사용하여 Service 인스턴스 생성
def get_bus_service(request: Request) -> BusTransitService:
    return BusTransitService(client=request.app.state.http_client)

@router.get(
    "/arrival",
    response_model=BusArrivalResponse,
    summary="버스 도착 정보 조회"
)
async def get_arrival_info(
    bus_number: str = Query(..., description="버스 번호"),
    station_name: str = Query(..., description="정류장 이름"),
    service: BusTransitService = Depends(get_bus_service)
):
    result = await service.get_arrival_info(bus_number, station_name)
    
    if not result:
        # Service는 데이터가 없으면 None을 리턴하고, 에러 처리는 Router가 담당
        raise HTTPException(
            status_code=404, 
            detail=f"Bus '{bus_number}' or Station '{station_name}' not found or API Error"
        )
    
    return result

@router.get(
    "/location",
    response_model=BusLocationResponse,
    summary="실시간 버스 위치 조회"
)
async def get_bus_location(
    veh_id: str = Query(..., description="버스 고유 ID (vehId)"),
    service: BusTransitService = Depends(get_bus_service)
):
    if not veh_id or veh_id == "0":
        raise HTTPException(status_code=400, detail="Invalid vehicle ID")

    result = await service.get_bus_location(veh_id)
    
    if not result:
        raise HTTPException(status_code=404, detail="Location not found")
        
    return result