# Python customer file service

FastAPI service exposing `GET /v1/customers/{customer_id}/files/{file_id}`.

- Requires an `X-API-Key` header, validates customer/file path components, and scopes the exercise token to one configured customer ID.
- Reads `customers/{customer_id}/{file_id}` from Cloud Storage when `GCS_BUCKET` is configured.
- Uses `demo-customer/welcome.txt` as a local in-memory fixture when no bucket is configured.
- Rejects files over 10 MiB and returns a generic 502 response for backend failures.
- Emits structured request logs without logging tokens or file contents.

The exercise token is scoped to one customer ID using `API_TOKEN_CUSTOMER_ID` (defaults to `demo-customer`). This demonstrates a tenant authorization check, but it is still a shared static token rather than a scalable customer identity system. Replace it with validated customer-scoped OIDC/JWT claims before production use.

## Local run

Requires Python 3.11+.

```sh
cd platform-file-service
python -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
export API_TOKEN=local-demo-token
export API_TOKEN_CUSTOMER_ID=demo-customer
uvicorn app.main:app --reload --port 8080
```

In another terminal:

```sh
curl -H 'X-API-Key: local-demo-token' \
  http://localhost:8080/v1/customers/demo-customer/files/welcome.txt
pytest -q
```

To use real Cloud Storage locally, also set `GCS_BUCKET` and configure Application Default Credentials with `gcloud auth application-default login`. The local API key is still required.

## Submission archive

From the repository root, create the requested zip with:

```sh
zip -r platform-file-service.zip platform-file-service \
  -x '*/.venv/*' '*/__pycache__/*' '*/.pytest_cache/*'
```

## Container

The Dockerfile runs as a non-root user on port 8080. Terraform injects `API_TOKEN` from Secret Manager, sets `GCS_BUCKET`, and configures `API_TOKEN_CUSTOMER_ID`; the token payload is not stored in Terraform state.
