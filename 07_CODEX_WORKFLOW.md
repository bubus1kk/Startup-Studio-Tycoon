# Startup Studio Tycoon — Codex Workflow

## 1. Роль Codex

Codex используется как инженер, а не одноразовый генератор.

Он должен изучать repo, планировать, реализовывать один этап, запускать проверки, делать self-review, объяснять риски и останавливаться на gate.

Он не должен расширять scope, переписывать архитектуру, помещать экономику на клиент, пропускать тесты или переходить дальше без команды.

## 2. `AGENTS.md`

Хранит:

- архитектурные границы;
- команды format/lint/build/test;
- структуру;
- Definition of Done;
- запреты;
- Git;
- save/monetization rules.

Полный game design туда не помещается — только ссылки.

## 3. Skills

```text
.agents/skills/<skill-name>/SKILL.md
```

Вызовы:

```text
$startup-roblox-architect
$phase-implementer
$studio-sync-and-verify
$economy-save-monetization-audit
$luau-strict-review
```

Для критичных задач использовать явно.

## 4. Цикл этапа

### A — Контекст

Открыть `AGENTS.md`, roadmap, development guide, checklist и существующие contracts/tests.

### B — Plan

```text
Use $startup-roblox-architect.
Plan Stage <N> only.
Do not edit files yet.
List modules, contracts, risks, tests, migrations and Studio checks.
```

### C — Implement

```text
Use $phase-implementer.
Implement Stage <N> exactly as defined.
Do not start the next stage.
```

### D — Review

```text
Use $luau-strict-review.
Review uncommitted changes.
Run format, lint, tests and Rojo build.
Fix high-confidence issues only.
```

### E — Studio

```text
Use $studio-sync-and-verify.
Verify Rojo paths, remotes and DataModel assumptions.
```

### F — Human QA

Выполнить `05_MANUAL_QA_GUIDE.md`.

### G — Fix

Передавать структурированный bug report.

### H — Commit

Просмотреть diff, затем commit.

## 5. Формат хорошего задания

Содержит stage, objective, scope, out of scope, acceptance, документы, команды, manual tests и stop condition.

```text
Implement Stage 5: Employees and NPC simulation.

Read:
- AGENTS.md
- 02_ROADMAP.md, Stage 5
- 03_DEVELOPMENT_GUIDE.md, NPC
- 04_STAGE_CHECKLIST.md, Stage 5

Scope:
- candidates
- hiring transaction
- desk assignment
- work state machine
- payroll
- productivity
- stuck recovery

Out of scope:
- product release
- monetization
- prestige

Before editing, provide a plan.
After editing, run checks and provide Studio scenarios.
Stop after Stage 5.
```

## 6. Плохие запросы

- «Сделай весь тайкун».
- «Исправь всё».
- «Сделай красиво».

У них нет scope, критериев и доказуемого завершения.

## 7. Контекст

- отдельный thread для крупного stage;
- указывать точные пути;
- не вставлять весь repo вручную;
- давать логи и bug report;
- не смешивать независимые дефекты;
- после этапа обновлять state summary и делать commit.

## 8. Защита от drift

```text
Use $startup-roblox-architect and identify whether this change violates an accepted boundary.
Do not implement an unapproved breaking change. Report first.
```

Breaking change требует причины, affected call sites, migration и решения пользователя.

## 9. MCP

Можно просить проверить DataModel paths, remotes, plot structure, Output и smoke test. MCP не заменяет визуальный, UX, mobile, monetization и final publish QA.

## 10. Approvals

Не разрешать без просмотра:

- удаление каталогов;
- reset/clean;
- push;
- production secrets;
- publish;
- массовое обновление зависимостей.

## 11. Self-review

```text
Review against:
1. AGENTS.md
2. stage acceptance
3. server-authoritative boundaries
4. strict Luau
5. remote validation
6. save/monetization idempotency
7. performance
8. Studio testability

List every unmet criterion. Do not claim completion if checks were not run.
```

## 12. Отчёт Codex

- summary;
- changed files;
- contracts;
- tests;
- commands and results;
- manual tests;
- risks;
- deferred;
- docs;
- gate status.

## 13. Вернуть на доработку, если

- изменён out-of-scope;
- tests не запускались;
- TODO вместо P0;
- client-authoritative price/reward;
- receipt не идемпотентен;
- schema без migration;
- UI — единственный state;
- нет error handling;
- нет manual steps;
- diff необъяснимо велик.

## 14. Режимы

- IDE — точечные правки и diff.
- CLI — tooling, tests, repo-wide analysis и skills.
- Cloud — независимые задачи, но Studio runtime обычно проверяется локально.

## 15. Формула

```text
Plan → Implement → Automated checks → Self-review → Studio QA → Fix → Acceptance → Commit
```
