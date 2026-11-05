from datetime import UTC, datetime

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.db import SessionLocal
from app.models import DiaryEntry

PATIENT_1 = {"Authorization": "Bearer patient-1"}
CLINICIAN_1 = {"Authorization": "Bearer clinician-1"}
CLINICIAN_2 = {"Authorization": "Bearer clinician-2"}
SHARE = {"clinician_id": 1, "from_date": "2026-10-01", "to_date": "2026-10-07"}


def create_entry(
    client: TestClient, recorded_at: str, note: str | None = None, mood: int = 3
) -> dict:
    body = {"recorded_at": recorded_at, "mood": mood, "symptoms": [], "note": note}
    return client.post("/entries", json=body, headers=PATIENT_1).json()


def test_no_valid_share_returns_empty_list_regardless_of_reason(client: TestClient) -> None:
    missing_patient = client.get("/clinician/patients/999/entries", headers=CLINICIAN_1)
    unshared_patient = client.get("/clinician/patients/1/entries", headers=CLINICIAN_1)

    assert missing_patient.status_code == unshared_patient.status_code == 200
    assert missing_patient.json() == unshared_patient.json() == []


def test_clinician_sees_only_entries_in_shared_range(client: TestClient) -> None:
    inside = create_entry(client, "2026-10-03T08:00:00Z")
    outside = create_entry(client, "2026-09-01T08:00:00Z")
    client.post("/shares", json=SHARE, headers=PATIENT_1)

    seen = client.get("/clinician/patients/1/entries", headers=CLINICIAN_1).json()
    assert [e["id"] for e in seen] == [inside["id"]]
    assert outside["id"] not in [e["id"] for e in seen]


def test_notes_hidden_unless_share_includes_them(client: TestClient) -> None:
    create_entry(client, "2026-10-03T08:00:00Z", note="private note")
    client.post("/shares", json=SHARE, headers=PATIENT_1)

    seen = client.get("/clinician/patients/1/entries", headers=CLINICIAN_1).json()
    assert seen[0]["note"] is None


def test_notes_shown_when_share_includes_them(client: TestClient) -> None:
    create_entry(client, "2026-10-03T08:00:00Z", note="private note")
    client.post("/shares", json={**SHARE, "include_notes": True}, headers=PATIENT_1)

    seen = client.get("/clinician/patients/1/entries", headers=CLINICIAN_1).json()
    assert seen[0]["note"] == "private note"


def test_calendar_day_uses_patient_timezone(client: TestClient) -> None:
    # Anna Becker (patient-1) is in Europe/Berlin. 22:30 UTC on Oct 7 is 00:30 CEST on Oct 8.
    entry = create_entry(client, "2026-10-07T22:30:00Z")

    client.post(
        "/shares",
        json={**SHARE, "from_date": "2026-10-07", "to_date": "2026-10-07"},
        headers=PATIENT_1,
    )
    assert client.get("/clinician/patients/1/entries", headers=CLINICIAN_1).json() == []

    client.post(
        "/shares",
        json={**SHARE, "from_date": "2026-10-08", "to_date": "2026-10-08"},
        headers=PATIENT_1,
    )
    seen = client.get("/clinician/patients/1/entries", headers=CLINICIAN_1).json()
    assert [e["id"] for e in seen] == [entry["id"]]


def test_app_v1_entries_use_stored_date_without_timezone_conversion(client: TestClient) -> None:
    # If this were wrongly converted Europe/Berlin -> UTC+2, 23:00 UTC would land on Oct 8.
    with SessionLocal() as db:
        entry = DiaryEntry(
            patient_id=1,
            recorded_at=datetime(2026, 10, 7, 23, 0, tzinfo=UTC),
            mood=3,
            symptoms=[],
            note=None,
            source="app-v1",
        )
        db.add(entry)
        db.commit()
        entry_id = entry.id

    client.post(
        "/shares",
        json={**SHARE, "from_date": "2026-10-07", "to_date": "2026-10-07"},
        headers=PATIENT_1,
    )

    seen = client.get("/clinician/patients/1/entries", headers=CLINICIAN_1).json()
    assert [e["id"] for e in seen] == [entry_id]


def test_union_of_overlapping_shares_from_same_clinician(client: TestClient) -> None:
    create_entry(client, "2026-10-03T08:00:00Z", note="secret")
    client.post("/shares", json=SHARE, headers=PATIENT_1)
    client.post(
        "/shares",
        json={**SHARE, "from_date": "2026-10-03", "to_date": "2026-10-03", "include_notes": True},
        headers=PATIENT_1,
    )

    seen = client.get("/clinician/patients/1/entries", headers=CLINICIAN_1).json()
    assert len(seen) == 1
    assert seen[0]["note"] == "secret"


def test_access_log_records_clinician_access_with_entry_ids(client: TestClient) -> None:
    entry = create_entry(client, "2026-10-03T08:00:00Z")
    client.post("/shares", json=SHARE, headers=PATIENT_1)

    client.get("/clinician/patients/1/entries", headers=CLINICIAN_1)

    log = client.get("/access-log", headers=PATIENT_1).json()
    assert len(log) == 1
    assert log[0]["clinician_id"] == 1
    assert log[0]["clinician_name"] == "Dr. Lena Hofmann"
    assert log[0]["entry_ids"] == [entry["id"]]


def test_access_log_records_zero_entry_access(client: TestClient) -> None:
    client.post("/shares", json=SHARE, headers=PATIENT_1)

    client.get("/clinician/patients/1/entries", headers=CLINICIAN_1)

    log = client.get("/access-log", headers=PATIENT_1).json()
    assert log[0]["entry_ids"] == []


def test_no_access_log_without_a_valid_share(client: TestClient) -> None:
    client.get("/clinician/patients/1/entries", headers=CLINICIAN_2)

    assert client.get("/access-log", headers=PATIENT_1).json() == []


def test_only_clinicians_can_read_patient_entries(client: TestClient) -> None:
    assert client.get("/clinician/patients/1/entries", headers=PATIENT_1).status_code == 403


def test_only_patients_can_read_their_access_log(client: TestClient) -> None:
    assert client.get("/access-log", headers=CLINICIAN_1).status_code == 403


def test_fails_closed_when_access_log_write_fails(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    create_entry(client, "2026-10-03T08:00:00Z")
    client.post("/shares", json=SHARE, headers=PATIENT_1)

    def broken_commit(self: Session) -> None:
        raise SQLAlchemyError("simulated failure")

    monkeypatch.setattr(Session, "commit", broken_commit)

    response = client.get("/clinician/patients/1/entries", headers=CLINICIAN_1)
    assert response.status_code == 503
    assert response.json() == {"detail": "Couldn't open the diary. Try again."}

    metrics = client.get("/metrics").text
    assert "access_log_write_failures_total 1.0" in metrics
