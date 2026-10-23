import pytest
from fastapi.testclient import TestClient

from app import main
from app.config import Settings


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(
        main,
        "settings",
        Settings(api_token="test-token", bucket="", log_level="INFO"),
    )
    return TestClient(main.app)
