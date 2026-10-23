from google.api_core.exceptions import NotFound

from app import main
from app.config import Settings


class FakeBlob:
    def __init__(self, data=b"cloud file", content_type="text/plain"):
        self.data = data
        self.size = len(data)
        self.content_type = content_type
        self.downloaded = False

    def reload(self):
        return None

    def download_as_bytes(self):
        self.downloaded = True
        return self.data


class FakeBucket:
    def __init__(self, blob):
        self._blob = blob
        self.requested_name = None

    def blob(self, name):
        self.requested_name = name
        return self._blob


class FakeStorageClient:
    def __init__(self, blob):
        self._bucket = FakeBucket(blob)

    def bucket(self, name):
        assert name == "test-files"
        return self._bucket


def test_health_endpoints(client):
    assert client.get("/health/live").json() == {"status": "ok"}
    assert client.get("/health/ready").json() == {"status": "ready"}


def test_local_fixture_requires_api_key_and_returns_attachment(client):
    path = "/v1/customers/demo-customer/files/welcome.txt"

    assert client.get(path).status_code == 401

    response = client.get(path, headers={"X-API-Key": "test-token"})

    assert response.status_code == 200
    assert response.text.startswith("Welcome to the customer file service.")
    assert response.headers["content-disposition"] == 'attachment; filename="welcome.txt"'
    assert response.headers["cache-control"] == "private, no-store"


def test_invalid_api_key_is_rejected(client):
    response = client.get(
        "/v1/customers/demo-customer/files/welcome.txt",
        headers={"X-API-Key": "wrong-token"},
    )

    assert response.status_code == 401


def test_local_missing_fixture_returns_404(client):
    response = client.get(
        "/v1/customers/demo-customer/files/missing.txt",
        headers={"X-API-Key": "test-token"},
    )

    assert response.status_code == 404


def test_invalid_identifiers_are_rejected(client):
    response = client.get(
        "/v1/customers/invalid.customer/files/welcome.txt",
        headers={"X-API-Key": "test-token"},
    )

    assert response.status_code == 400


def test_reads_customer_scoped_object_from_gcs(client, monkeypatch):
    blob = FakeBlob()
    storage_client = FakeStorageClient(blob)
    monkeypatch.setattr(main, "settings", Settings("test-token", "test-files", "INFO"))
    monkeypatch.setattr(main, "get_storage_client", lambda: storage_client)

    response = client.get(
        "/v1/customers/demo-customer/files/report.pdf",
        headers={"X-API-Key": "test-token"},
    )

    assert response.status_code == 200
    assert response.content == b"cloud file"
    assert storage_client._bucket.requested_name == "customers/demo-customer/report.pdf"
    assert blob.downloaded


def test_oversized_gcs_object_is_rejected_before_download(client, monkeypatch):
    blob = FakeBlob()
    blob.size = main.MAX_FILE_SIZE_BYTES + 1
    monkeypatch.setattr(main, "settings", Settings("test-token", "test-files", "INFO"))
    monkeypatch.setattr(main, "get_storage_client", lambda: FakeStorageClient(blob))

    response = client.get(
        "/v1/customers/demo-customer/files/large.bin",
        headers={"X-API-Key": "test-token"},
    )

    assert response.status_code == 413
    assert not blob.downloaded


def test_backend_failure_uses_generic_error(client, monkeypatch):
    class BrokenBlob(FakeBlob):
        def reload(self):
            raise RuntimeError("sensitive storage detail")

    monkeypatch.setattr(main, "settings", Settings("test-token", "test-files", "INFO"))
    monkeypatch.setattr(main, "get_storage_client", lambda: FakeStorageClient(BrokenBlob()))

    response = client.get(
        "/v1/customers/demo-customer/files/file-1",
        headers={"X-API-Key": "test-token"},
    )

    assert response.status_code == 502
    assert response.json() == {"detail": "File retrieval failed"}
    assert "sensitive storage detail" not in response.text


def test_missing_gcs_object_returns_404(client, monkeypatch):
    class MissingBlob(FakeBlob):
        def reload(self):
            raise NotFound("missing")

    monkeypatch.setattr(main, "settings", Settings("test-token", "test-files", "INFO"))
    monkeypatch.setattr(main, "get_storage_client", lambda: FakeStorageClient(MissingBlob()))

    response = client.get(
        "/v1/customers/demo-customer/files/missing.txt",
        headers={"X-API-Key": "test-token"},
    )

    assert response.status_code == 404
