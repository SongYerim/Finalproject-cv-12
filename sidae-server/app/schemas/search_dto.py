from pydantic import BaseModel, Field

class LocationResponse(BaseModel):
    name: str = Field(..., description="장소명")
    address: str = Field("", description="주소")
    latitude: float = Field(..., description="위도")
    longitude: float = Field(..., description="경도")
