# Startup Studio Tycoon — Stage Acceptance Checklist

Ответ Codex «готово» не является доказательством.

## Общие проверки

- [ ] Scope не расширен.
- [ ] Codex перечислил изменённые файлы.
- [ ] Нет случайных изменений.
- [ ] `stylua --check` проходит.
- [ ] `selene` проходит.
- [ ] `rojo build` проходит.
- [ ] Тесты проходят.
- [ ] Studio без новых ошибок.
- [ ] Проверен server/client boundary.
- [ ] Документация обновлена.
- [ ] Ручная проверка выполнена.
- [ ] Diff просмотрен.
- [ ] Коммит создан после приёмки.

## Stage 0 — Product baseline

- [ ] game design;
- [ ] launch-ready scope;
- [ ] after-launch;
- [ ] risk register;
- [ ] device support;
- [ ] performance assumptions;
- [ ] нет противоречивых валют;
- [ ] prestige однозначен;
- [ ] monetization не блокирует core loop.

## Stage 1 — Toolchain

- [ ] Git repo;
- [ ] `default.project.json`;
- [ ] `rokit.toml`;
- [ ] `stylua.toml`;
- [ ] `selene.toml`;
- [ ] `.gitignore`;
- [ ] `AGENTS.md`;
- [ ] skills;
- [ ] CI;
- [ ] `rojo build`;
- [ ] `rojo serve`;
- [ ] plugin connected;
- [ ] bootstrap starts.

Вероятные баги: неверные `$path`, mismatch версий, firewall/port, build files в Git.

## Stage 2 — Architecture

- [ ] service registry;
- [ ] remote registry;
- [ ] logger;
- [ ] config validation;
- [ ] shared types;
- [ ] feature flags;
- [ ] deterministic bootstrap;
- [ ] duplicate service rejected;
- [ ] duplicate remote rejected;
- [ ] missing dependency reported;
- [ ] server-only data not replicated.

## Stage 3 — Plots

- [ ] unique plot;
- [ ] release on leave;
- [ ] starter office;
- [ ] ownership server-side;
- [ ] foreign requests rejected;
- [ ] Start Server + 3 Players tested;
- [ ] simultaneous join tested;
- [ ] no orphaned plot.

## Stage 4 — Building

- [ ] `PlotRuntimeModel.PrimaryPart` остаётся стабильным `PlotAnchor`, а plot spawn/boundary ownership не меняется;
- [ ] Garage создаётся только `OfficeBuildingService`, без двойных floor/walls;
- [ ] покупка rooms, equipment, furniture, upgrades и tier transitions проходит через server-owned catalog;
- [ ] initial Garage имеет цену 0 и сразу `Purchased`; остальные definitions имеют integer `price > 0`;
- [ ] prerequisite graph, tier, ownership, duplicate и equipment slot проверяются сервером;
- [ ] клиент не передаёт price, balance, plot/owner, prerequisite state, anchor или `CFrame`;
- [ ] deterministic anchors и placement keys восстанавливают одинаковый layout;
- [ ] `PlotBounds` и `OfficeGeometryValidator` проверяют bounds, overlaps, room envelopes, doorway, spawn и entrance path;
- [ ] каждый tier содержит один local-space `EntranceApproach`, по которому игрок проходит от стабильного `SpawnLocation` до пола офиса без прыжка;
- [ ] общий entrance geometry contract одновременно управляет physical approach и полным validation envelope без hardcoded path;
- [ ] все 50 server-only templates содержат уникальную category-specific geometry, достижимы из catalog и не выходят за authoritative envelopes;
- [ ] duplicate/concurrent request не создаёт второй item и не списывает Cash повторно;
- [ ] failed generation/commit откатывает reservation, layout и pending root без orphan Instances;
- [ ] tier/upgrade replacement оставляет ровно один canonical `OfficeBuildRoot`;
- [ ] `OfficePurchaseResponse.state` использует только `Available | Purchased | Locked | MaxLevel | Pending`;
- [ ] catalog pagination имеет page size 5, stable sorting и bounded payload;
- [ ] persistent HUD Build button переживает respawn без duplicate UI/connections;
- [ ] menu отключён до готовности office session, а закрытие UI не отменяет server transaction;
- [ ] InvokeServer exception очищает pending и допускает retry; stale catalog response и callback после Destroy не меняют UI;
- [ ] Development/Test/Production получают явно заданные provisional Stage 4 session funds 250000;
- [ ] full catalog стоит 205150, достижим и оставляет Cash 44850;
- [ ] destroy/rebuild и bounded same-server snapshot round-trip проходят без DataStore;
- [ ] snapshot TTL/capacity используют injected monotonic clock и lazy eviction;
- [ ] Solo и Start Server + 3 Players manual QA выполнены;
- [ ] maximum-content generation и rebuild performance проверены в Studio profiler;
- [ ] локальный Stage Acceptance Plugin собран, вручную установлен и `Stage 4 Full` вернул структурированный результат через `StudioTestService:EndTest`;
- [ ] runtime result содержит минимум 72 реально выполненных server tests (61 functional unit/integration + 11 plugin orchestration), а не фиксированный PASS count;
- [ ] production/test remotes, probes и fixtures изолированы;
- [ ] `scripts/Test-Stage1.ps1` … `scripts/Test-Stage4.ps1`, lint и оба Rojo build проходят.

Stage 4 snapshot не является persistent cross-server save. DataStore/ProfileService/session locking/autosave остаются Stage 9; полноценная экономика остаётся Stage 8, polished UI framework — Stage 10.

## Stage 5 — Employees

- [x] authoritative config содержит ровно 9 roles, 4 grades, 3 stats, 12 traits и tier caps до 30;
- [x] Candidate Board содержит ровно 3 server-generated кандидата, TTL 300 секунд, manual refresh cooldown 120 секунд и доступного кандидата при достижимом hire;
- [x] expired/consumed candidate ID отклоняется точным безопасным кодом, а request replay не делает второй debit/hire;
- [x] пять Stage 5 RemoteFunctions централизованы вместе с двумя Stage 4 RemoteFunctions; payload shape/range/size и per-call node budget валидируются;
- [x] клиент не передаёт hiring cost, salary, grade, traits, stats, morale, XP, productivity, Cash, timestamps, ownership, plot или CFrame;
- [x] hiring transaction проверяет owner/session/tier cap/compatible desk/Cash и откатывает reservation при failure;
- [x] workstation IDs стабильны, capacities имеют префикс L1/L2/L3 и дают суммарно 30 слотов на L3;
- [x] один desk не может быть занят двумя сотрудниками, foreign/incompatible/occupied desk отклоняется;
- [x] upgrade/rebuild сохраняет доступные stable assignments; удалённый desk освобождает assignment и не оставляет stale reservation;
- [x] payroll выполняет один atomic total reservation раз в 60 секунд без partial debit/negative Cash;
- [x] `Active → Unpaid → Inactive` и recovery обратно в `Active` применяют contract morale/output multipliers без automatic dismissal;
- [x] productivity, role ledger, XP/levels, morale bands, Recreation Lounge и HR recovery вычисляются сервером из конфигов;
- [x] нет passive morale decay, fatigue, product assignment, product revenue или offline productivity;
- [x] один централизованный scheduler обслуживает productivity/candidates/payroll; stuck scan работает раз в 0.5 секунды без permanent loop/script на NPC;
- [x] NPC создаются server-side, ограничены plot bounds, имеют bounded path request budget и deterministic fallback recovery;
- [x] join order — Plot → Currency → Office → Workstations → Employees; cleanup идёт в обратном порядке и удаляет NPC/attachments/connections;
- [x] same-server snapshot имеет `schemaVersion`, восстанавливает roster/assignment/ledger/deadlines и не заявляет cross-server persistence;
- [x] persistent Employees UI имеет Candidates/Team, pagination, countdowns, confirmation dismiss, pending/error/stale/destroy safety;
- [x] unit/integration/client tests и structural `scripts/Test-Stage5.ps1` добавлены, CI и оба Rojo проекта обновлены;
- [ ] Studio `Stage 5 Runtime` выполнен и содержит не менее 98 реально выполненных server tests;
- [ ] Studio `Stage 5 Solo` подтверждает три candidate cards, Developer hire с exact debit/auto-assignment, NPC path, work points/XP, refresh cooldown, UI respawn safety и dismiss cleanup;
- [ ] Studio `Stage 5 MP3` подтверждает ownership isolation и cleanup;
- [ ] Studio `Stage 5 NPC 10`, `Stage 5 NPC 30` и profiler подтверждают бюджеты без дублированных NPC/scripts;
- [ ] Studio `Stage 5 Blocked Path` подтверждает bounded recovery и отсутствие выхода за plot;
- [ ] локальный Stage Acceptance Plugin вручную установлен, `Stage 5 Full` (динамически 3030 секунд при текущих suite definitions) прошёл все 10 suites и результат сохранён.

Stage 5 gate остаётся открытым до выполнения перечисленных Studio-сценариев. DataStore/ProfileService/session locking/autosave остаются Stage 9; products/release/revenue начинаются только в Stage 6.

## Stage 6 — Product vertical slice

- [ ] product creation;
- [ ] legal stages;
- [ ] progress;
- [ ] QA effect;
- [ ] server release;
- [ ] duplicate release rejected;
- [ ] revenue stream;
- [ ] result explanation;
- [ ] deterministic score test;
- [ ] clamps;
- [ ] zero/max team cases.

## Stage 7 — Portfolio

- [ ] five categories;
- [ ] lifecycle;
- [ ] maintenance;
- [ ] hype decay;
- [ ] technical debt;
- [ ] slots;
- [ ] sunset;
- [ ] market modifiers;
- [ ] no dominant category;
- [ ] no infinite growth without sinks.

## Stage 8 — Economy/prestige

- [ ] ledger everywhere;
- [ ] no negative balance;
- [ ] research prerequisites;
- [ ] automation limits;
- [ ] tiers;
- [ ] Reputation;
- [ ] prestige preview;
- [ ] idempotent prestige;
- [ ] spam requests tested;
- [ ] stale UI price tested;
- [ ] first prestige balanced.

## Stage 9 — Saves

- [ ] autosave;
- [ ] milestone saves;
- [ ] session lock;
- [ ] migrations;
- [ ] reconcile;
- [ ] offline income;
- [ ] shutdown;
- [ ] fallback;
- [ ] normal/fast rejoin;
- [ ] old schema;
- [ ] missing fields;
- [ ] published test.

Блокеры: потеря валюты, дюп, два сервера на профиль, destructive migration.

## Stage 10 — UI/UX

- [ ] desktop;
- [ ] mobile;
- [ ] gamepad;
- [ ] safe zones;
- [ ] scaling;
- [ ] no duplicate connections;
- [ ] resumable tutorial;
- [ ] loading/error states;
- [ ] dynamic prices;
- [ ] first-session test.

## Stage 11 — Social/co-op

- [ ] visits;
- [ ] reactions;
- [ ] leaderboard;
- [ ] party;
- [ ] co-op contract;
- [ ] contribution;
- [ ] anti-farming;
- [ ] privacy;
- [ ] repeated reward rejected;
- [ ] owner leave;
- [ ] client contribution spoof rejected.

## Stage 12 — Monetization

- [ ] IDs centralized;
- [ ] dynamic prices;
- [ ] receipt processor;
- [ ] idempotency;
- [ ] pending grants;
- [ ] pass ownership;
- [ ] subscription;
- [ ] analytics;
- [ ] environment separation;
- [ ] receipt retry;
- [ ] disconnect after payment;
- [ ] unknown ID;
- [ ] grant failure;
- [ ] consumable repeat.

## Stage 13 — LiveOps

- [ ] daily;
- [ ] weekly;
- [ ] event configs;
- [ ] timestamps;
- [ ] reward idempotency;
- [ ] feature flags;
- [ ] unknown event handling;
- [ ] before/start/during/end/after tests;
- [ ] day boundary;
- [ ] server time.

## Stage 14 — Release candidate

### Security
- [ ] remotes reviewed;
- [ ] validation;
- [ ] rate limits;
- [ ] ownership;
- [ ] no client economy;
- [ ] no replicated secrets.

### Performance
- [ ] Script Profiler;
- [ ] MicroProfiler;
- [ ] target players;
- [ ] target NPC;
- [ ] 30–60 minute soak;
- [ ] memory stable;
- [ ] network reviewed.

### Release
- [ ] private beta;
- [ ] rollback tag;
- [ ] previous build saved;
- [ ] release notes;
- [ ] production IDs;
- [ ] production DataStore config;
- [ ] analytics verified;
- [ ] rating checked;
- [ ] blocker/critical = 0.
