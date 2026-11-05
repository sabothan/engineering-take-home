# CLAUDE.md

Symptom diary take-home (Kranus Health). Feature: "Share my diary with my doctor", end to end,
in a 2-hour timebox. I must be able to explain every line, so work in small steps I can review.

## Read before changing anything

`BRIEF.md` (what to build), `API.md` (fixed contract), `REQUIREMENTS.md` (must meet),
`app/DESIGN.md` (UI rules). If code and these files disagree, stop and tell me.

## Commands

All tooling runs in Docker via make. Never install Python, Flutter or packages on the host.

- `make test-api` / `make test-app` / `make test`: run after every change
- `make lint`: before you say a step is done
- `make migration m="..."` then `make restart`: new migration, applied to the dev DB
- `make app`: rebuild the Flutter web app

## Hard constraints

- `API.md` is a contract other teams and Kranus's own tests rely on. Implement it exactly:
  paths, status codes, field names. No extra response fields.
- Do not change the responses of `GET /entries` or `GET /me` (`EntryOut`, `Me`). App v2.3
  parses them strictly and crashes on any change.
- No health data (mood, symptoms, notes) and no direct identifiers in application logs.
- No patient or clinician IDs, names or free text as metric labels. Labels must have a small,
  fixed set of values.
- Access records are audit evidence, not logs: database only, IDs only, never edited or deleted.
- Share dates are calendar days in the patient's time zone (`patients.timezone`). Use
  `zoneinfo`, never UTC dates. `app-v1` entries store local time as if it were UTC.
- A clinician must not be able to tell "no such patient" from "not shared with you".
- Keep the existing tests green. Don't modify existing tests to make them pass.
- Don't touch `.devcontainer/`, `Makefile`, `docker-compose.yml` unless I ask.

## Decisions

Design decisions are mine. When the docs leave something open, don't pick silently: present the
options with their trade-offs and wait for my choice. I record each decision in `NOTES.md`.

## How to work with me

- One step at a time. Before changing code, state a short plan in this form:
  `1. [step] → verify: [check]`, then change it.
- Prefer the smallest change that meets the requirement. No refactors I didn't ask for.
- Tests first or alongside, in `backend/tests/` and `app/test/`.
- State every assumption explicitly so I can copy it into `NOTES.md`.
- If you're unsure whether something meets a requirement, say so and name the requirement ID.
- Never commit or push. I do that.
- Follow `app/DESIGN.md` for any Flutter code: theme tokens, `ContentColumn`, patient words.

## Editing existing code

- Touch only what the step needs. Don't "improve" neighbouring code, comments or formatting.
- Match the existing style, even if you'd write it differently.
- Remove imports, variables or functions that your change made unused. Leave pre-existing dead
  code alone; mention it instead.
- Every changed line must trace back to the current step.
