from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # NAVER Cloud Platform (Dynamic Map, Geocoding, Reverse Geocoding)
    NCP_MAPS_CLIENT_ID: str
    NCP_MAPS_CLIENT_SECRET: str

    # NAVER Search API (지역 검색, POI)
    NAVER_SEARCH_CLIENT_ID: str
    NAVER_SEARCH_CLIENT_SECRET: str

    # SK TMAP API (Tmap 경로 탐색)
    SK_API_KEY: str

    # 환경 설정 (.env 파일을 읽어오도록 설정)
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = True

# 설정 인스턴스
settings = Settings()