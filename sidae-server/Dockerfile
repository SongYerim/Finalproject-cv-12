FROM python:3.12.10-slim

# 로그가 실시간으로 출력되도록 설정
ENV PYTHONUNBUFFERED=1

# 컨테이너 기본 경로 설정
WORKDIR /sidae-server

# 컨테이너 사용 포트
EXPOSE 8000

# 라이브러리 설치
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 소스 코드 복사
COPY . .

# FastAPI 실행
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]