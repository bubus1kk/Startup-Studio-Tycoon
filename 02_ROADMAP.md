# Startup Studio Tycoon — Production Roadmap

## Общие правила

- Один этап реализуется и принимается полностью.
- Каждый этап заканчивается автоматическими проверками, Studio-тестом и Git-коммитом.
- Система сначала получает контракт, конфиг и тестируемую бизнес-логику, затем UI и визуал.
- Не выполнять массовый рефакторинг принятого кода без отдельного решения.
- Сохранения и монетизация проектируются заранее.
- Код остаётся server-authoritative.

## Stage 0 — Product baseline and scope lock

**Цель:** зафиксировать правила игры, launch-ready scope и технические ограничения.

**Задачи:** утвердить game design; определить устройства и max players; performance budgets; валюты; список v1/after-launch; risk register; naming.

**Gate:** нет противоречий; все P0 перечислены; есть критерии готовности.

**Сложность:** низкая.

## Stage 1 — Toolchain, repository and reproducible build

**Цель:** получить воспроизводимый файловый проект.

**Задачи:** Git; Rokit; Rojo; StyLua; Selene; Wally; `default.project.json`; структура `src`; `AGENTS.md`; skills; Studio plugin; MCP; `.gitignore`; CI.

**Gate:** `rojo build`, `rojo serve`, format, lint и CI успешны; bootstrap без ошибок.

**Сложность:** средняя.

## Stage 2 — Architecture foundation and contracts

**Цель:** создать стабильный каркас сервисов и контрактов.

**Задачи:** lifecycle Init/Start/Destroy; shared types; config loader; constants; remote registry; validation; logging; errors; feature flags; environment config; deterministic startup.

**Gate:** сервисы запускаются детерминированно; remotes не дублируются; серверные данные не реплицируются.

**Сложность:** высокая.

## Stage 3 — Player session, plot ownership and office shell

**Цель:** каждому игроку выдать изолированный plot и стартовый офис.

**Задачи:** allocation; ownership; join/leave cleanup; deterministic generation; boundaries; spawn; server validation.

**Gate:** три игрока получают разные plot; уход освобождает plot; чужой клиент не изменяет чужой офис.

**Сложность:** высокая.

## Stage 4 — Building, rooms and office progression

**Цель:** покупка комнат, мебели и апгрейдов.

**Задачи:** room configs; prerequisite graph; server transaction; anchors; templates; equipment slots; build menu; visualization; tier unlock; rollback.

**Gate:** стоимость вычисляет сервер; нет дублей; layout восстанавливается; построение не выходит за plot.

**Сложность:** высокая.

## Stage 5 — Employees and NPC simulation

**Цель:** найм, назначение, движение и работа сотрудников.

**Задачи:** candidates; data model; roles; hiring; desk assignment; pathfinding; stuck recovery; state machine; payroll; morale; productivity; controlled spawning.

**Gate:** все роли работают; payroll server-side; нет двойных desk; path failure не ломает цикл; cleanup при выходе.

**Сложность:** очень высокая.

## Stage 6 — Product development vertical slice

**Цель:** один продукт от идеи до дохода.

**Задачи:** state machine; team assignment; progress; quality/bugs/hype; release; revenue; result UI; maintenance.

**Gate:** все стадии работают; release нельзя вызвать дважды; результат и доход рассчитывает сервер.

**Сложность:** очень высокая.

## Stage 7 — Full portfolio and market simulation

**Цель:** полноценная продуктовая мета.

**Задачи:** пять категорий; demand; lifecycle; hype decay; maintenance; technical debt; slots; dashboard; sunset; events; balancing configs.

**Gate:** категории различаются; нет одной лучшей; старые продукты требуют решений; числа находятся в конфиге.

**Сложность:** высокая.

## Stage 8 — Economy, research, automation and prestige

**Цель:** долгосрочная прогрессия.

**Задачи:** ledger; source/sink tags; research; automation; tiers; Reputation; Founder Points; preview; prestige transaction; permanent perks; soft-lock recovery.

**Gate:** валюты не отрицательны; prestige идемпотентен; понятен reset; первый prestige проверен.

**Сложность:** очень высокая.

## Stage 9 — Save system, migrations and offline progression

**Цель:** надёжное сохранение.

**Задачи:** profile schema; session locking; autosave; milestone saves; version; migrations; reconcile; fallback; offline cap; shutdown handling; test/prod separation.

**Gate:** rejoin работает; старая схема мигрирует; два сервера не редактируют один профиль; offline не зависит от клиента.

**Сложность:** критическая.

## Stage 10 — UI/UX, tutorial and accessibility

**Цель:** понятная игра на всех устройствах.

**Задачи:** UI architecture; state layer; HUD; menus; tutorial; notifications; input abstraction; responsive layouts; controller focus; reduced effects.

**Gate:** первый релиз достижим без внешней инструкции; mobile/gamepad работают; UI не является источником денег; tutorial продолжается после rejoin.

**Сложность:** очень высокая.

## Stage 11 — Multiplayer social and cooperative systems

**Цель:** безопасный social surface.

**Задачи:** visits; reactions; showcase; leaderboard; party; co-op contract; contribution; anti-farming; privacy.

**Gate:** посещение не даёт ownership; награды server-side; нельзя получить reward дважды.

**Сложность:** высокая.

## Stage 12 — Monetization

**Цель:** продажи без нарушения стабильности.

**Задачи:** configs; dynamic prices; prompt flow; receipt processor; idempotent grant ledger; ownership; subscription; analytics; environment IDs; retry handling.

**Gate:** consumables повторяются корректно; pass не выдаётся как consumable; receipt не подтверждается до grant; disconnect не теряет покупку.

**Сложность:** критическая.

## Stage 13 — Daily quests, events and LiveOps

**Цель:** обновляемый контент через конфиги.

**Задачи:** daily/weekly engine; progress events; rewards; schedule; feature flags; modifiers; fallback; admin-safe toggles; expiry.

**Gate:** reward не дублируется; событие можно отключить без deploy; даты server-side.

**Сложность:** высокая.

## Stage 14 — Security, performance, analytics and release candidate

**Цель:** подготовить release candidate.

**Задачи:** threat review; rate limits; permissions; memory leak sweep; profilers; target-player test; soak; analytics; localization readiness; rating; release notes; rollback; private beta; staged publish.

**Gate:** blocker/critical = 0; normal gameplay без console errors; save/load и purchases проверены в опубликованном test experience; есть rollback tag.

**Сложность:** критическая.

## Ветки

```text
main
stage/01-foundation
stage/02-architecture
stage/03-plots
...
stage/14-release-candidate
fix/stage-05-npc-stuck-recovery
spike/new-pathfinding-strategy
```

Spike не сливается напрямую в `main`; рабочее решение переносится в нормальную ветку.
