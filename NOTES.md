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

## Data model decisions

## Requirements

| ID | Applies? | Where it is met (code, test), or why not |
| --- | --- | --- |
| O.Purp_1 | | |
| O.Cons_1 | | |
| O.Cons_2 | | |
| O.Cons_3 | | |
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
