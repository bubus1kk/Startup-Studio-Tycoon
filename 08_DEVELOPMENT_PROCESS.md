# Startup Studio Tycoon — Development Process

## 1. Инициализация

1. Создать private GitHub repo.
2. Скопировать документы.
3. Установить инструменты.
4. Создать toolchain files.
5. Запустить Codex с `09_PROMPT_FOR_CODEX.md`.
6. Реализовать только Stage 1.
7. Принять Stage 1.
8. Поставить tag `stage-01-accepted`.

## 2. Git workflow

Ветки:

- `main` — только принятые этапы;
- `stage/NN-name` — этап;
- `feature/name` — часть;
- `fix/name` — исправление;
- `spike/name` — эксперимент.

Правила:

- не работать в `main`;
- перед stage обновить `main`;
- commit имеет одну цель;
- build files не коммитить;
- no force push to main;
- не смешивать массовый format с feature.

Commit format:

```text
feat(employee): add server-side hiring transaction
fix(save): prevent duplicate offline claim
test(product): cover release score clamps
docs(stage-05): add NPC manual QA steps
chore(tooling): configure Selene
```

## 3. Stage branch

```powershell
git checkout main
git pull
git checkout -b stage/05-employees
```

Проверки:

```powershell
git status
git diff
stylua --check src tests
selene src tests
rojo build -o build/StartupStudioTycoon.rbxl
```

После QA:

```powershell
git add .
git commit -m "feat(employee): complete employee and NPC stage"
git push -u origin stage/05-employees
```

После merge:

```powershell
git checkout main
git pull
git tag stage-05-accepted
git push --tags
```

## 4. Разбиение stage

Пример Employees:

1. types/config;
2. candidate generation;
3. hiring;
4. desk assignment;
5. NPC spawn;
6. state machine;
7. recovery;
8. payroll;
9. productivity;
10. UI;
11. tests;
12. QA.

Каждый slice оставляет проект запускаемым. Не создавать десятки пустых skeleton-файлов.

## 5. Ежедневный цикл

Начало:

- `git status`;
- обновить branch;
- baseline checks;
- одна задача;
- точный prompt.

Во время:

- смотреть diff;
- не накапливать необъяснённые изменения;
- запускать быстрые tests;
- фиксировать решения.

Конец:

- format/lint/tests/build;
- Studio smoke;
- commit;
- state note;
- не оставлять сломанный branch без отметки.

## 6. Документы

- `01_GAME_DESIGN.md` — продукт.
- `02_ROADMAP.md` — порядок.
- `03_DEVELOPMENT_GUIDE.md` — технические правила.
- `04_STAGE_CHECKLIST.md` — gate.
- `05_MANUAL_QA_GUIDE.md` — ручные тесты.
- `09_PROMPT_FOR_CODEX.md` — запуск.
- `AGENTS.md` — постоянные правила.

## 7. Приёмка Codex

Проверить scope, changed files, duplicate architecture, tests, команды, TODO, docs, Studio, regression и возможность rollback.

## 8. Bug fix

Передать build, environment, steps, expected, actual, frequency, Output и player state.

```text
Use $startup-roblox-architect and $luau-strict-review.
Fix this bug with the smallest safe change.
Do not refactor unrelated systems.
Add a regression test where practical.
Provide exact Studio retest steps.
<BUG REPORT>
```

## 9. Изменение требований

1. изменить game design;
2. impact analysis;
3. roadmap;
4. data migration;
5. отдельная branch;
6. реализация.

Save schema нельзя менять «по ходу».

## 10. Dependencies

Пакет добавляется, если проблема реальна, пакет поддерживается, лицензия приемлема, код просмотрен, сложность оправдана, версия закреплена и есть fallback.

## 11. Release

Ветка:

```text
release/1.0.0-rc.1
```

Процесс:

1. code freeze;
2. only fixes;
3. private beta;
4. save compatibility;
5. monetization test;
6. profiler;
7. rollback rehearsal;
8. tag `v1.0.0`;
9. publish;
10. monitoring.

## 12. Версионирование

SemVer для repo. Save schema — отдельное целое число.

## 13. Rollback

- предыдущая Roblox version;
- Git tag;
- production config snapshot;
- active IDs;
- feature flags;
- старые migrations сохраняются.

## 14. После релиза

Следить за error rate, save failures, receipt failures, onboarding, first release funnel, server performance, economy anomalies и exploit reports.

## 15. Запреты

- merge при красном CI;
- publish из непроверенной branch;
- production DataStore для local debug;
- IDs в нескольких файлах;
- удаление migration сразу после релиза;
- большой refactor перед release.
