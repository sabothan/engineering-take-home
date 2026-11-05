from fastapi.testclient import TestClient

PATIENT_1 = {"Authorization": "Bearer patient-1"}
PATIENT_2 = {"Authorization": "Bearer patient-2"}
SHARE = {"clinician_id": 1, "from_date": "2026-10-01", "to_date": "2026-10-07"}


def test_patient_creates_and_lists_own_shares(client: TestClient) -> None:
    created = client.post("/shares", json=SHARE, headers=PATIENT_1)
    assert created.status_code == 201
    body = created.json()
    assert body["clinician_id"] == 1
    assert body["from_date"] == "2026-10-01"
    assert body["to_date"] == "2026-10-07"
    assert body["include_notes"] is False
    assert body["revoked_at"] is None

    shares = client.get("/shares", headers=PATIENT_1).json()
    assert [s["id"] for s in shares] == [body["id"]]


def test_include_notes_defaults_to_false_but_can_be_set(client: TestClient) -> None:
    created = client.post("/shares", json={**SHARE, "include_notes": True}, headers=PATIENT_1)
    assert created.json()["include_notes"] is True


def test_patient_does_not_see_other_patients_shares(client: TestClient) -> None:
    client.post("/shares", json=SHARE, headers=PATIENT_1)

    assert client.get("/shares", headers=PATIENT_2).json() == []


def test_shares_are_newest_first(client: TestClient) -> None:
    first = client.post("/shares", json=SHARE, headers=PATIENT_1).json()
    second = client.post("/shares", json=SHARE, headers=PATIENT_1).json()

    ids = [s["id"] for s in client.get("/shares", headers=PATIENT_1).json()]
    assert ids == [second["id"], first["id"]]


def test_rejects_unknown_clinician(client: TestClient) -> None:
    response = client.post("/shares", json={**SHARE, "clinician_id": 999}, headers=PATIENT_1)
    assert response.status_code == 422


def test_rejects_to_date_before_from_date(client: TestClient) -> None:
    invalid = {**SHARE, "from_date": "2026-10-07", "to_date": "2026-10-01"}
    assert client.post("/shares", json=invalid, headers=PATIENT_1).status_code == 422


def test_shares_are_for_patients_only(client: TestClient) -> None:
    headers = {"Authorization": "Bearer clinician-1"}
    assert client.post("/shares", json=SHARE, headers=headers).status_code == 403
    assert client.get("/shares", headers=headers).status_code == 403


def test_patient_revokes_own_share(client: TestClient) -> None:
    created = client.post("/shares", json=SHARE, headers=PATIENT_1).json()

    revoked = client.post(f"/shares/{created['id']}/revoke", headers=PATIENT_1)
    assert revoked.status_code == 200
    assert revoked.json()["revoked_at"] is not None


def test_revoke_is_idempotent(client: TestClient) -> None:
    created = client.post("/shares", json=SHARE, headers=PATIENT_1).json()

    first = client.post(f"/shares/{created['id']}/revoke", headers=PATIENT_1).json()
    second = client.post(f"/shares/{created['id']}/revoke", headers=PATIENT_1).json()
    assert first["revoked_at"] == second["revoked_at"]


def test_cannot_revoke_another_patients_share(client: TestClient) -> None:
    created = client.post("/shares", json=SHARE, headers=PATIENT_1).json()

    response = client.post(f"/shares/{created['id']}/revoke", headers=PATIENT_2)
    assert response.status_code == 404


def test_revoking_unknown_share_is_404(client: TestClient) -> None:
    assert client.post("/shares/999/revoke", headers=PATIENT_1).status_code == 404
