# AGENTS.md

## Project

Startup Studio Tycoon is a production-ready Roblox simulation/tycoon developed with Rojo and strict Luau practices.

## Authoritative documents

Before non-trivial work read:

- `01_GAME_DESIGN.md`
- `02_ROADMAP.md`
- `03_DEVELOPMENT_GUIDE.md`
- `04_STAGE_CHECKLIST.md`
- `05_MANUAL_QA_GUIDE.md`
- `07_CODEX_WORKFLOW.md`
- `08_DEVELOPMENT_PROCESS.md`

## Architecture

- Server authoritative for all persistent or economic state.
- Client is presentation and input only.
- Shared modules contain types, constants, configs and pure helpers.
- Server-only modules and secrets never replicate.
- Remotes are centralized and validated.
- Balance and product IDs are centralized.
- Use config-first and contract-first design.
- Avoid side effects during `require`.

## Luau

- Prefer `--!strict`.
- Export public types.
- Avoid `any`.
- Use guard clauses.
- Handle nil explicitly.
- Clean event connections.
- Avoid unbounded loops.
- Do not use deprecated `wait()`.
- Do not mutate caller-owned tables without a contract.

## Security

Never trust client-provided prices, amounts, timestamps, rewards, ownership, productivity, release scores or purchase completion.

Validate type, range, ownership, state, cooldown and rate.

## Saves

- Every schema has `schemaVersion`.
- Changes require migration.
- Offline time is server-side.
- Profiles use session locking.
- Reconcile missing fields.
- Never store Instances or Player objects.
- Do not confirm receipt before successful idempotent grant.

## Required checks

Expected baseline:

```bash
stylua --check src tests
selene src tests
pwsh -NoProfile -File scripts/Test-Stage1.ps1
pwsh -NoProfile -File scripts/Test-Stage2.ps1
pwsh -NoProfile -File scripts/Test-Stage3.ps1
rojo build -o build/StartupStudioTycoon.rbxl
rojo build test.project.json -o build/StartupStudioTycoonStage3Tests.rbxl
```

The PowerShell commands above are structural suites. GitHub Actions does not execute Roblox Studio. Stage 2 and Stage 3 Luau runtime specs require a manual Studio run of `test.project.json` until a separately approved CLI runner exists. If a command cannot run, report it.

## Stage rules

- One stage at a time.
- Plan before editing.
- Do not start next stage.
- Do not expand scope.
- TODO is not P0 completion.
- Preserve accepted APIs.
- Breaking changes require impact and migration.

## Documentation

Update setup, commands, contracts, save schema, remotes, configs, QA and checklist when changed.

## Git safety

Do not commit, push, merge, reset, clean, tag or publish unless explicitly requested.

## Completion report

Provide summary, changed files, contracts, tests, commands/results, Studio tests, risks, deferred items and gate status.
