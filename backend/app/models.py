from datetime import date, datetime

from sqlalchemy import CheckConstraint, Date, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class Patient(Base):
    """A patient account.

    Attributes:
        timezone: IANA zone name (e.g. "Europe/Berlin"), used to resolve which calendar day a
            diary entry or a share's date range falls on.
    """

    __tablename__ = "patients"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    email: Mapped[str] = mapped_column(String(320), unique=True)
    timezone: Mapped[str] = mapped_column(String(64))  # IANA name, e.g. "Europe/Berlin"
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Clinician(Base):
    """A doctor who may be granted read access to a patient's diary via a :class:`Share`."""

    __tablename__ = "clinicians"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    practice: Mapped[str] = mapped_column(String(200))


class DiaryEntry(Base):
    """One mood/symptom/note record a patient logged.

    Attributes:
        source: "app-v2" (default) for normal entries, or "app-v1" for entries written by the
            old app, whose ``recorded_at`` holds local wall-clock time mislabelled as UTC.
    """

    __tablename__ = "diary_entries"
    __table_args__ = (CheckConstraint("mood BETWEEN 1 AND 5", name="mood_range"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    patient_id: Mapped[int] = mapped_column(ForeignKey("patients.id"), index=True)
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    mood: Mapped[int]
    symptoms: Mapped[list[str]] = mapped_column(ARRAY(Text), default=list)
    note: Mapped[str | None] = mapped_column(Text)
    # "app-v1" entries were sent without a time zone and stored as if they were UTC.
    source: Mapped[str] = mapped_column(String(16), server_default="app-v2")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Share(Base):
    """A patient's consent to let one clinician read their diary for a date range.

    Doubles as the consent record for O.Cons_1/O.Cons_3: it is valid exactly while
    ``revoked_at`` is ``None``, and it scopes exactly what was consented to (clinician, date
    range, whether notes are included).

    Attributes:
        from_date: First calendar day covered (inclusive), in the patient's timezone.
        to_date: Last calendar day covered (inclusive), in the patient's timezone.
        consent_version: Wording version of the consent text agreed to (O.Cons_3). Internal
            only; never exposed via the API.
        revoked_at: When the patient stopped sharing, or ``None`` if still active.
    """

    __tablename__ = "shares"
    __table_args__ = (CheckConstraint("to_date >= from_date", name="share_date_range"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    patient_id: Mapped[int] = mapped_column(ForeignKey("patients.id"), index=True)
    clinician_id: Mapped[int] = mapped_column(ForeignKey("clinicians.id"))
    from_date: Mapped[date] = mapped_column(Date)
    to_date: Mapped[date] = mapped_column(Date)
    include_notes: Mapped[bool] = mapped_column(default=False, server_default="false")
    # The wording of the consent text the patient agreed to when creating this share (O.Cons_3).
    # Internal only; not part of the API.md response.
    consent_version: Mapped[str] = mapped_column(String(32), server_default="v1")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)


class AccessLog(Base):
    """Audit evidence that a clinician read a patient's diary (O.Log_1-3).

    Rows are written once and never updated or deleted; no code path in this app issues
    UPDATE/DELETE against this table.

    Attributes:
        accessed_at: When the read happened.
        entry_ids: Ids of the entries actually returned, frozen at access time.
    """

    __tablename__ = "access_logs"

    id: Mapped[int] = mapped_column(primary_key=True)
    patient_id: Mapped[int] = mapped_column(ForeignKey("patients.id"), index=True)
    clinician_id: Mapped[int] = mapped_column(ForeignKey("clinicians.id"))
    accessed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    entry_ids: Mapped[list[int]] = mapped_column(ARRAY(Integer), default=list)
