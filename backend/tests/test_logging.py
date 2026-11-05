import logging

import pytest
from fastapi.testclient import TestClient

ENTRY = {
    "recorded_at": "2026-10-05T08:30:00+02:00",
    "mood": 4,
    "symptoms": ["headache"],
    "note": "Slept badly",
}


def test_request_log_does_not_contain_entry_body(
    client: TestClient, caplog: pytest.LogCaptureFixture
) -> None:
    with caplog.at_level(logging.INFO, logger="diary.requests"):
        client.post("/entries", json=ENTRY, headers={"Authorization": "Bearer patient-1"})

    log_text = "\n".join(record.getMessage() for record in caplog.records)
    assert "headache" not in log_text
    assert "Slept badly" not in log_text
    assert "POST /entries -> 201" in log_text
