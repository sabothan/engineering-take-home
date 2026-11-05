from datetime import date, datetime

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator


class EntryIn(BaseModel):
    recorded_at: AwareDatetime
    mood: int = Field(ge=1, le=5)
    symptoms: list[str] = Field(default_factory=list, max_length=20)
    note: str | None = Field(default=None, max_length=2000)


class EntryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    recorded_at: datetime
    mood: int
    symptoms: list[str]
    note: str | None


class ClinicianOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    practice: str


class ShareIn(BaseModel):
    clinician_id: int
    from_date: date
    to_date: date
    include_notes: bool = False

    @model_validator(mode="after")
    def check_date_range(self) -> "ShareIn":
        if self.to_date < self.from_date:
            raise ValueError("to_date must not be before from_date")
        return self


class ShareOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    clinician_id: int
    from_date: date
    to_date: date
    include_notes: bool
    created_at: datetime
    revoked_at: datetime | None


class AccessLogOut(BaseModel):
    clinician_id: int
    clinician_name: str
    accessed_at: datetime
    entry_ids: list[int]


class TelemetryEvent(BaseModel):
    event: str = Field(pattern=r"^[a-z][a-z0-9_]{0,63}$")


class Me(BaseModel):
    role: str
    id: int
    name: str
