FROM python:3.12.10-slim

# 로그가 실시간으로 출력되도록 설정
ENV PYTHONUNBUFFERED=1

# GCP가 주입할 포트 번호 (기본값 8001)
ENV PORT=8001

# 컨테이너 기본 경로 설정
WORKDIR /sidae-server

# 라이브러리 설치 (캐시 최적화를 위해 먼저 수행)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 소스 코드 복사
COPY . .

# 컨테이너 사용 포트 노출
EXPOSE 8001

# [수정된 부분] sh -c를 사용하여 변수를 정상적으로 인식하게 합니다.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]