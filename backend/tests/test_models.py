from datetime import date

import pytest
from sqlalchemy.exc import IntegrityError

from app.db import SessionLocal
from app.models import AccessLog, Share

# Seeded by seed_users() via the clean_db fixture: id=1 is patient-1/clinician-1.
PATIENT_1 = 1
CLINICIAN_1 = 1


def test_share_rejects_to_date_before_from_date() -> None:
    with SessionLocal() as db:
        db.add(
            Share(
                patient_id=PATIENT_1,
                clinician_id=CLINICIAN_1,
                from_date=date(2026, 10, 7),
                to_date=date(2026, 10, 1),
            )
        )
        with pytest.raises(IntegrityError, match="share_date_range"):
            db.commit()


def test_share_rejects_unknown_patient() -> None:
    with SessionLocal() as db:
        db.add(
            Share(
                patient_id=999,
                clinician_id=CLINICIAN_1,
                from_date=date(2026, 10, 1),
                to_date=date(2026, 10, 7),
            )
        )
        with pytest.raises(IntegrityError):
            db.commit()


def test_share_rejects_unknown_clinician() -> None:
    with SessionLocal() as db:
        db.add(
            Share(
                patient_id=PATIENT_1,
                clinician_id=999,
                from_date=date(2026, 10, 1),
                to_date=date(2026, 10, 7),
            )
        )
        with pytest.raises(IntegrityError):
            db.commit()


def test_share_defaults() -> None:
    with SessionLocal() as db:
        share = Share(
            patient_id=PATIENT_1,
            clinician_id=CLINICIAN_1,
            from_date=date(2026, 10, 1),
            to_date=date(2026, 10, 7),
        )
        db.add(share)
        db.commit()
        db.refresh(share)

        assert share.include_notes is False
        assert share.consent_version == "v1"
        assert share.revoked_at is None
        assert share.created_at is not None


def test_access_log_entry_ids_defaults_to_empty_list() -> None:
    with SessionLocal() as db:
        log = AccessLog(patient_id=PATIENT_1, clinician_id=CLINICIAN_1)
        db.add(log)
        db.commit()
        db.refresh(log)

        assert log.entry_ids == []
        assert log.accessed_at is not None


def test_access_log_rejects_unknown_patient() -> None:
    with SessionLocal() as db:
        db.add(AccessLog(patient_id=999, clinician_id=CLINICIAN_1, entry_ids=[]))
        with pytest.raises(IntegrityError):
            db.commit()


def test_access_log_rejects_unknown_clinician() -> None:
    with SessionLocal() as db:
        db.add(AccessLog(patient_id=PATIENT_1, clinician_id=999, entry_ids=[]))
        with pytest.raises(IntegrityError):
            db.commit()
