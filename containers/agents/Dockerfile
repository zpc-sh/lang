# Minimal agent container that speaks LSP over TCP
FROM python:3.11-slim

WORKDIR /app
COPY agent.py /app/agent.py

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

ENTRYPOINT ["python", "/app/agent.py"]

