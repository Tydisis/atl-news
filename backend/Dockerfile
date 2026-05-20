FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app


FROM base AS deps
COPY requirements.txt ./
RUN pip install --prefix=/install -r requirements.txt


FROM base AS runtime

RUN groupadd --system --gid 1000 atl && \
    useradd  --system --uid 1000 --gid atl --home /app atl

COPY --from=deps /install /usr/local
COPY app ./app

USER atl

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2).status==200 else 1)"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
