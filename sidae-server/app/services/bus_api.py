# app/services/bus_api.py
import httpx
from urllib.parse import unquote
from app.core.config import settings
from app.schemas.bus_info import BusArrivalResponse, BusLocationResponse

class BusTransitService:
    BASE_URL = "http://ws.bus.go.kr/api/rest"
    
    def __init__(self, client: httpx.AsyncClient):
        self.client = client
        self.service_key = unquote(settings.BUS_KEY)

    async def get_route_id(self, bus_number: str) -> str | None:
        """버스 번호로 노선 ID를 조회합니다."""
        url = f"{self.BASE_URL}/busRouteInfo/getBusRouteList"
        params = {
            'serviceKey': self.service_key,
            'strSrch': bus_number,
            'resultType': 'json'
        }
        
        try:
            response = await self.client.get(url, params=params)
            data = response.json()
            
            if data['msgHeader']['headerCd'] != '0':
                return None
            
            for item in data['msgBody']['itemList']:
                if item['busRouteNm'] == bus_number:
                    return item['busRouteId']
            return None
        except Exception as e:
            print(f"Error getting route ID: {e}")
            return None

    async def get_arrival_info(self, bus_number: str, station_name: str) -> BusArrivalResponse | None:
        """버스 도착 정보를 조회합니다."""
        # 1. 노선 ID 조회
        route_id = await self.get_route_id(bus_number)
        if not route_id:
            return None

        # 2. 전체 정류장 도착 정보 조회
        url = f"{self.BASE_URL}/arrive/getArrInfoByRouteAll"
        params = {
            'serviceKey': self.service_key,
            'busRouteId': route_id,
            'resultType': 'json'
        }

        try:
            response = await self.client.get(url, params=params)
            data = response.json()

            if data['msgHeader']['headerCd'] != '0':
                return None
            
            item_list = data['msgBody'].get('itemList')
            if not item_list:
                return None

            # 3. 정류장 매칭
            for info in item_list:
                if info['stNm'] == station_name:
                    return BusArrivalResponse(
                        bus_number=bus_number,
                        station_name=station_name,
                        status_msg=info['arrmsg1'],
                        plate_no=info['plainNo1'],
                        veh_id=info['vehId1'],
                        station_seq=str(info['staOrd'])
                    )
            return None # 해당 정류장을 못 찾음
        except Exception as e:
            print(f"Error getting arrival info: {e}")
            return None

    async def get_bus_location(self, veh_id: str) -> BusLocationResponse | None:
        """버스 실시간 위치를 조회합니다."""
        url = f"{self.BASE_URL}/buspos/getBusPosByVehId"
        params = {
            'serviceKey': self.service_key,
            'vehId': veh_id,
            'resultType': 'json'
        }

        try:
            response = await self.client.get(url, params=params)
            data = response.json()

            if data['msgHeader']['headerCd'] != '0':
                return None

            if data['msgBody'].get('itemList'):
                pos = data['msgBody']['itemList'][0]
                return BusLocationResponse(
                    veh_id=veh_id,
                    tmX=float(pos['tmX']),
                    tmY=float(pos['tmY']),
                    data_tm=pos.get('dataTm')
                )
            return None
        except Exception as e:
            print(f"Error getting location: {e}")
            return None