# Notes

Date: 2026-11-05

Start: 12:33
Pause: 12:42 - 13:04: _Caused by setup problems on my side_.

End: **TODO**

Time spent: **TODO**

## Assumptions and open questions

- Before starting the feature, found a pre-existing O.Log_4 violation: the request-logging
  middleware in `backend/app/main.py` logged the full raw request body at INFO, which leaked
  health data for `POST /entries` (and would have for the new `POST /shares` too). Fixed by
  dropping the body read and the `body=%s` field from the log call, rather than redacting
  individual fields, since no caller needs the body in logs and a redaction list would rot as
  the schema changes. Verified: `POST /entries` now logs only `METHOD PATH -> STATUS in N ms`.

- No uniqueness constraint on `shares`: a patient can have multiple concurrent, non-revoked
  shares with the same doctor (e.g. overlapping or repeated date ranges). Neither `API.md` nor
  `BRIEF.md` rules this out, so I didn't add one to avoid constraining something that wasn't
  asked for.

## Data model decisions

- `shares` table (`backend/app/models.py`): `patient_id`/`clinician_id` as FKs, `from_date`/
  `to_date` as plain `Date` columns (calendar days, no time component) — the patient-timezone
  conversion happens when matching diary entries to the range, not when storing the share, since
  the share itself is just "these calendar days" per `BRIEF.md`. `include_notes` defaults to
  `false`. `revoked_at` nullable, set on revoke, never deleted (keeps the row as evidence of what
  was shared and for how long).
- Added `consent_version` to `shares`: an internal-only column (not in any `API.md` response),
  recording the wording version the patient agreed to when creating the share, for O.Cons_3. The
  share row itself is treated as the consent record: it's valid (grants access) exactly while
  `revoked_at IS NULL`, and captures exactly what was consented to (clinician, date range,
  whether notes are included) per O.Cons_1.

## Requirements

| ID | Applies? | Where it is met (code, test), or why not |
| --- | --- | --- |
| O.Purp_1 | | |
| O.Cons_1 | | |
| O.Cons_2 | | |
| O.Cons_3 | Yes | `shares.consent_version` (internal, not in the API response) records the consent wording version at creation time. See "Data model decisions". |
| O.Auth_1 | | |
| O.Pass_1 | | |
| O.Log_1 | | |
| O.Log_2 | | |
| O.Log_3 | | |
| O.Log_4 | Yes | Was violated: request-logging middleware (`backend/app/main.py`, `log_requests`) logged the full request body, leaking `mood`/`symptoms`/`note`. Fixed by removing the body read and the `body=%s` log field. |
| O.Mon_1 | | |
| O.Err_1 | | |
| O.Cryp_1 | | |
| O.Del_1 | | |
| O.Doc_1 | | |

## Erasure (O.Del_1): how I would do it

## Monitoring

What would we want to know, how do you measure it, and when should someone act?

## Screenshots

## How I used AI

Tools, workflow, and where you corrected the agent. Session transcripts are welcome but optional.

## Next steps
