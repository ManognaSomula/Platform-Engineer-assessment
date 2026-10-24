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

## Assessment core principles

### Testability: unit and integration tests

Run the automated suite from this directory with `pytest -q`. The tests cover health endpoints, missing and incorrect API keys, identifier validation, the configured customer boundary, successful fixture and mocked-GCS retrieval, missing files, oversized files, and generic backend errors. GCS behavior is tested with a fake client, so these are automated application tests rather than tests against a live bucket. A separate manual integration check was performed against the deployed service through the Cloud Run proxy: the expected customer file returned HTTP 200, and a request for another customer returned HTTP 403. Run the tests in your environment before saying that the suite passes.

### Simplicity: clean, readable code

`app/main.py` follows a direct request flow: authenticate, validate the path identifiers, check the configured customer, retrieve the object, and form the response. `app/config.py` keeps environment-based settings separate from the route logic. The service deliberately has one endpoint and a small local fixture for development.

### Security: input validation and authentication

The service validates customer and file identifiers, requires `X-API-Key`, compares the key with `hmac.compare_digest`, and limits the exercise token to the configured `API_TOKEN_CUSTOMER_ID`. It rejects files above the 10 MiB example limit and returns generic backend errors. Responses use `private, no-store`, attachment, and `nosniff` headers. This is a demonstration boundary, not production customer identity: replace the shared token with validated customer-scoped OIDC/JWT claims before production use.

### Observability: logging and monitoring

The app emits structured JSON request logs with route, status, and duration, and logs backend failures without exposing credentials or file contents. Cloud Run provides platform-level request metrics and logs. The application does not currently export custom metrics or distributed traces, and this project does not provision SLO dashboards or alert policies. Those are follow-up work; throughput and latency objectives still need representative load testing.
