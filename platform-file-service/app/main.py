import hmac
import json
import logging
import re
import time
from functools import lru_cache

from fastapi import Depends, FastAPI, Header, HTTPException, Request, status
from fastapi.responses import Response
from google.api_core.exceptions import NotFound
from google.cloud import storage

from app.config import settings

MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024
CUSTOMER_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")
FILE_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
LOCAL_FIXTURE = {
    ("demo-customer", "welcome.txt"): (b"Welcome to the customer file service.\n", "text/plain")
}


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "severity": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
        }
        if hasattr(record, "json_fields"):
            payload.update(record.json_fields)
        return json.dumps(payload, separators=(",", ":"))


handler = logging.StreamHandler()
handler.setFormatter(JsonFormatter())
logging.basicConfig(level=settings.log_level, handlers=[handler], force=True)
logger = logging.getLogger("file_service")

app = FastAPI(title="Customer File Retrieval", version="1.0.0")


def require_api_key(x_api_key: str | None = Header(default=None, alias="X-API-Key")) -> None:
    if not settings.api_token:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Service authentication is not configured",
        )
    if x_api_key is None or not hmac.compare_digest(
        x_api_key.encode("utf-8"), settings.api_token.encode("utf-8")
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid API key",
            headers={"WWW-Authenticate": "ApiKey"},
        )


@lru_cache(maxsize=1)
def get_storage_client() -> storage.Client:
    return storage.Client()


@app.middleware("http")
async def log_request(request: Request, call_next):
    started = time.perf_counter()
    response = None
    try:
        response = await call_next(request)
        return response
    finally:
        route = request.scope.get("route")
        logger.info(
            "request completed",
            extra={
                "json_fields": {
                    "method": request.method,
                    "route": getattr(route, "path", "unmatched"),
                    "status": response.status_code if response else 500,
                    "duration_ms": round((time.perf_counter() - started) * 1000, 2),
                }
            },
        )


@app.get("/health/live", include_in_schema=False)
def liveness():
    return {"status": "ok"}


@app.get("/health/ready", include_in_schema=False)
def readiness():
    if not settings.api_token:
        raise HTTPException(status_code=503, detail="Service authentication is not configured")
    return {"status": "ready"}


@app.get(
    "/v1/customers/{customer_id}/files/{file_id}",
    dependencies=[Depends(require_api_key)],
)
def retrieve_file(customer_id: str, file_id: str):
    if not CUSTOMER_ID_PATTERN.fullmatch(customer_id) or not FILE_ID_PATTERN.fullmatch(file_id):
        raise HTTPException(status_code=400, detail="Invalid customer or file identifier")

    if not settings.bucket:
        fixture = LOCAL_FIXTURE.get((customer_id, file_id))
        if fixture is None:
            raise HTTPException(status_code=404, detail="File not found")
        data, content_type = fixture
    else:
        object_name = f"customers/{customer_id}/{file_id}"
        try:
            blob = get_storage_client().bucket(settings.bucket).blob(object_name)
            blob.reload()
            if blob.size is not None and blob.size > MAX_FILE_SIZE_BYTES:
                raise HTTPException(status_code=413, detail="File exceeds the 10 MiB example limit")
            data = blob.download_as_bytes()
            if len(data) > MAX_FILE_SIZE_BYTES:
                raise HTTPException(status_code=413, detail="File exceeds the 10 MiB example limit")
            content_type = blob.content_type or "application/octet-stream"
        except NotFound as exc:
            raise HTTPException(status_code=404, detail="File not found") from exc
        except HTTPException:
            raise
        except Exception as exc:
            logger.warning("file backend request failed", extra={"json_fields": {"error_type": type(exc).__name__}})
            raise HTTPException(
                status_code=502,
                detail="File retrieval failed",
            ) from exc

    return Response(
        content=data,
        media_type=content_type,
        headers={
            "Cache-Control": "private, no-store",
            "Content-Disposition": f'attachment; filename="{file_id}"',
            "X-Content-Type-Options": "nosniff",
        },
    )
