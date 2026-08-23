# FastAPI BFF for the Neo4j Operations Console
FROM python:3.12-slim

WORKDIR /app

COPY python/requirements.txt /app/python/requirements.txt
RUN pip install --no-cache-dir -r /app/python/requirements.txt

COPY python /app/python
COPY cypher /app/cypher
COPY monitoring /app/monitoring
COPY admin /app/admin

ENV PYTHONPATH=/app
ENV API_HOST=0.0.0.0
ENV API_PORT=8000

EXPOSE 8000
CMD ["python", "-m", "uvicorn", "python.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
