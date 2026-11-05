import logging
from collections.abc import Sequence
from datetime import UTC, date, datetime
from typing import Annotated
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.auth import User, current_clinician, current_patient, current_user
from app.db import get_db
from app.metrics import ACCESS_LOG_WRITE_FAILURES, APP_EVENTS
from app.models import AccessLog, Clinician, DiaryEntry, Patient, Share
from app.schemas import (
    AccessLogOut,
    ClinicianOut,
    EntryIn,
    EntryOut,
    Me,
    ShareIn,
    ShareOut,
    TelemetryEvent,
)

logger = logging.getLogger("diary.access")

router = APIRouter()

Db = Annotated[Session, Depends(get_db)]
AnyUser = Annotated[User, Depends(current_user)]
PatientUser = Annotated[User, Depends(current_patient)]
ClinicianUser = Annotated[User, Depends(current_clinician)]


@router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/me", response_model=Me)
def me(user: AnyUser) -> User:
    return user


@router.get("/clinicians", response_model=list[ClinicianOut])
def list_clinicians(_: AnyUser, db: Db) -> Sequence[Clinician]:
    return db.scalars(select(Clinician).order_by(Clinician.name)).all()


@router.get("/entries", response_model=list[EntryOut])
def list_entries(user: PatientUser, db: Db) -> Sequence[DiaryEntry]:
    query = (
        select(DiaryEntry)
        .where(DiaryEntry.patient_id == user.id)
        .order_by(DiaryEntry.recorded_at.desc())
    )
    return db.scalars(query).all()


@router.post("/entries", response_model=EntryOut, status_code=201)
def create_entry(body: EntryIn, user: PatientUser, db: Db) -> DiaryEntry:
    entry = DiaryEntry(patient_id=user.id, **body.model_dump())
    db.add(entry)
    db.commit()
    db.refresh(entry)
    return entry


@router.post("/shares", response_model=ShareOut, status_code=201)
def create_share(body: ShareIn, user: PatientUser, db: Db) -> Share:
    """Grants a clinician consent to read the caller's diary for a date range (O.Cons_1).

    Args:
        body: The clinician, date range and whether to include notes.
        user: The authenticated patient.
        db: Database session.

    Returns:
        The created share.

    Raises:
        HTTPException: 422, if ``clinician_id`` doesn't exist.
    """
    if db.get(Clinician, body.clinician_id) is None:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Unknown clinician_id")
    share = Share(patient_id=user.id, **body.model_dump())
    db.add(share)
    db.commit()
    db.refresh(share)
    return share


@router.get("/shares", response_model=list[ShareOut])
def list_shares(user: PatientUser, db: Db) -> Sequence[Share]:
    """Lists the caller's shares, newest first."""
    query = select(Share).where(Share.patient_id == user.id).order_by(Share.created_at.desc())
    return db.scalars(query).all()


@router.post("/shares/{share_id}/revoke", response_model=ShareOut)
def revoke_share(share_id: int, user: PatientUser, db: Db) -> Share:
    """Withdraws consent for a share, effective immediately for any later read (O.Cons_2).

    Idempotent: revoking an already-revoked share just returns its current state.

    Raises:
        HTTPException: 404, if the share doesn't exist or belongs to another patient (the two
            are deliberately indistinguishable).
    """
    share = db.scalar(select(Share).where(Share.id == share_id, Share.patient_id == user.id))
    if share is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Share not found")
    if share.revoked_at is None:
        share.revoked_at = datetime.now(UTC)
        db.commit()
        db.refresh(share)
    return share


@router.get("/access-log", response_model=list[AccessLogOut])
def list_access_log(user: PatientUser, db: Db) -> list[dict[str, object]]:
    """Lists who has read the caller's diary, newest first (O.Log_2)."""
    query = (
        select(AccessLog, Clinician.name)
        .join(Clinician, Clinician.id == AccessLog.clinician_id)
        .where(AccessLog.patient_id == user.id)
        .order_by(AccessLog.accessed_at.desc())
    )
    return [
        {
            "clinician_id": log.clinician_id,
            "clinician_name": name,
            "accessed_at": log.accessed_at,
            "entry_ids": log.entry_ids,
        }
        for log, name in db.execute(query)
    ]


@router.get("/clinician/patients/{patient_id}/entries", response_model=list[EntryOut])
def list_patient_entries_for_clinician(
    patient_id: int, user: ClinicianUser, db: Db
) -> list[dict[str, object]]:
    """Returns exactly the entries the caller's active shares for this patient cover.

    Records the access (O.Log_1) and fails closed (503) if that recording fails, rather than
    disclosing health data that couldn't be proven audited (O.Mon_1).

    Args:
        patient_id: The patient whose diary is being read.
        user: The authenticated clinician.
        db: Database session.

    Returns:
        Visible entries, newest first, with ``note`` nulled out unless a covering share
        includes notes. Empty whether the patient doesn't exist, was never shared with, or
        revoked the share: those cases must be indistinguishable to the clinician.

    Raises:
        HTTPException: 503, if the access could not be recorded.
    """
    shares = db.scalars(
        select(Share).where(
            Share.patient_id == patient_id,
            Share.clinician_id == user.id,
            Share.revoked_at.is_(None),
        )
    ).all()
    if not shares:
        # Same empty response whether the patient doesn't exist, was never shared with this
        # clinician, or revoked the share: a clinician must not be able to tell those apart.
        return []

    patient = db.get(Patient, patient_id)
    assert patient is not None  # an active share can only exist for a real patient (FK)
    tz = ZoneInfo(patient.timezone)

    def local_date(entry: DiaryEntry) -> date:
        # app-v1 entries stored local wall-clock time mislabelled as UTC: use it as-is.
        if entry.source == "app-v1":
            return entry.recorded_at.date()
        return entry.recorded_at.astimezone(tz).date()

    entries = db.scalars(
        select(DiaryEntry)
        .where(DiaryEntry.patient_id == patient_id)
        .order_by(DiaryEntry.recorded_at.desc())
    ).all()

    visible = []
    for entry in entries:
        day = local_date(entry)
        covering = [s for s in shares if s.from_date <= day <= s.to_date]
        if not covering:
            continue
        visible.append(
            {
                "id": entry.id,
                "recorded_at": entry.recorded_at,
                "mood": entry.mood,
                "symptoms": entry.symptoms,
                "note": entry.note if any(s.include_notes for s in covering) else None,
            }
        )

    try:
        db.add(
            AccessLog(
                patient_id=patient_id,
                clinician_id=user.id,
                entry_ids=[e["id"] for e in visible],
            )
        )
        db.commit()
    except SQLAlchemyError:
        db.rollback()
        ACCESS_LOG_WRITE_FAILURES.inc()
        logger.error("Failed to record a clinician's diary access; the read was not served.")
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, "Couldn't open the diary. Try again."
        ) from None

    return visible


@router.post("/telemetry", status_code=204)
def telemetry(body: TelemetryEvent, _: AnyUser) -> Response:
    APP_EVENTS.labels(body.event).inc()
    return Response(status_code=204)
