import pytest
from fastapi.testclient import TestClient

from app.main import app


def test_unhandled_error_does_not_leak_internals(monkeypatch: pytest.MonkeyPatch) -> None:
    def boom(*args: object, **kwargs: object) -> None:
        raise RuntimeError("something broke in /srv/app/db.py, see traceback")

    monkeypatch.setattr("app.api.select", boom)

    with TestClient(app, raise_server_exceptions=False) as client:
        response = client.get("/entries", headers={"Authorization": "Bearer patient-1"})

    assert response.status_code == 500
    body = response.text
    assert "Traceback" not in body
    assert "RuntimeError" not in body
    assert "db.py" not in body
    assert "sqlalchemy" not in body.lower()
