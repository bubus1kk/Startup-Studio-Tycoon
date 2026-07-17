# Startup Studio Tycoon — Manual QA Guide

## 1. Что проверяет человек

Codex может проверить файлы, код, lint и часть тестов. Человек обязан проверить:

- реальное поведение в Roblox Studio;
- удобство UI;
- визуальные ошибки;
- pathfinding;
- multiplayer replication;
- сохранения в опубликованном experience;
- purchase flows в тестовой среде;
- производительность;
- баланс;
- понятность onboarding.

## 2. Режимы Studio

- **Play** — быстрый smoke test.
- **Play Here** — проверка конкретной зоны.
- **Start Server + 1 Player** — client-server границы.
- **Start Server + 3 Players** — plot ownership и replication.
- **Device Emulator** — экраны и input.
- **Published private test experience** — DataStore, monetization и server transitions.

## 3. Приёмка этапа

1. Получить список изменённых файлов.
2. Просмотреть diff.
3. Выполнить автоматические команды.
4. Перезапустить `rojo serve`.
5. Подключить Studio.
6. Очистить Output.
7. Запустить happy path.
8. Запустить error path.
9. Запустить spam/repeat path.
10. Запустить multiplayer path.
11. Проверить rejoin, если затронуты данные.
12. Проверить profiler для циклов/NPC/UI.
13. Записать дефекты.
14. Не принимать этап при blocker/critical.

## 4. Severity

- **Blocker** — невозможно запустить или продолжить тест.
- **Critical** — потеря данных, дюп, exploit, потеря покупки.
- **Major** — основная функция не работает.
- **Minor** — работает с заметной ошибкой.
- **Trivial** — косметика.

## 5. Bug report

```md
# BUG: <название>

## Severity
Critical / Major / Minor / Trivial

## Build
commit SHA / tag

## Environment
Studio / published test
Play / Start Server
Desktop / mobile / gamepad

## Preconditions
Профиль, офис, сотрудники, продукты.

## Steps to reproduce
1.
2.
3.

## Expected
Ожидаемое поведение.

## Actual
Фактическое поведение.

## Frequency
Always / Often / Rare / Once

## Evidence
Screenshot, video, Output, Developer Console, profiler.

## Suspected area
Необязательно.
```

## 6. Обязательные сценарии

### Architecture foundation

- production Play: server/client bootstrap без ошибок;
- Server & Clients: `PlayerScripts.Infrastructure` может появиться после запуска Bootstrap, но client ждёт его не более 10 секунд и затем успешно пишет `client_bootstrap_ready`;
- при намеренно отсутствующем client dependency Output содержит `StartupError` и `StartupDependencyTimeout`, а test session не пишет финальный `PASS all`;
- три перезапуска: одинаковый startup order;
- `ReplicatedStorage.Remotes` существует и не содержит gameplay remotes;
- `ServerConfig` и server registries отсутствуют в `ReplicatedStorage`;
- test place: duplicate service, missing dependency и cycle отклоняются;
- test place: Init/Start rollback и reverse cleanup проходят;
- test place с клиентом: invalid remote payload не достигает handler;
- test place: test-only remotes отсутствуют после cleanup;
- production build не содержит `Stage2Tests`, `TestSupport` и test remotes.

### Plot

- в production place запустить **Start Server + 3 Players**;
- дождаться трёх `AssignedPlotId` и проверить `plot_01`, `plot_02`, `plot_03` без дублей;
- все игроки имеют разные `AssignedPlotId`, `PlotId` и `OwnerUserId`;
- каждый character находится перед входом именно своего plot, а не у общего/центрального spawn;
- starter shell и низкая boundary frame одинаковы на всех plots;
- spawn находится перед входом и смотрит в сторону офиса;
- до reset в `Workspace.Map.Plots` ровно три runtime model;
- выполнить **Reset Character** последовательно на каждом из трёх клиентов;
- после каждого reset `AssignedPlotId` не меняется и character возвращается на `SpawnLocation` своего plot;
- после всех reset в `Workspace.Map.Plots` по-прежнему ровно три runtime model, duplicate office отсутствует;
- владелец выходит;
- его runtime model и обе ownership-связи исчезают;
- новый игрок получает свободный plot;
- освобождённый plot создаётся заново без объектов прошлого владельца;
- в test place owner вызывает `TestPlotMutation` для своего plot и получает success;
- другой клиент вызывает `TestPlotMutation` для чужого plot и получает `PlotOwnershipMismatch` без изменения mutation count;
- после failure/release/Destroy test/debug orphan validation проходит;
- production place не содержит `Stage3TestRemotes` и `TestPlotMutation`.

### Building

- перед ручными сценариями собрать и установить локальный runner по `docs/STAGE_4_AUTOMATED_ACCEPTANCE.md`, открыть Stage 4 test place и сохранить полный результат `Stage 4 Full` из dock widget/Output;
- **Solo:** HUD Build button появляется один раз, `B` открывает то же меню, категории/цены/locked state корректны; Garage уже `Purchased`;
- Игрок проходит от SpawnLocation до Garage без прыжка, затем после полного progression проходит тем же способом до Global HQ;
- купить Development Room, её equipment/furniture, оба upgrade level и проверить `Available → Purchased`, `L2 → Available`, `L3 → MaxLevel`;
- попытаться купить locked room/tier до prerequisite и убедиться, что Cash/layout не меняются;
- недостаточно Cash и ровно достаточно Cash: ответ сервера отображается, state не становится ошибочно `Locked`/`Purchased`, balance не отрицателен;
- двойной клик, повтор того же `requestId`, новый `requestId` для уже купленного item и 50–100 spam calls не создают duplicate model/debit;
- invalid category/page и oversized payload отклоняются; invalid page непустой категории возвращает её реальные `pageCount`/`totalItems` и пустой `items`;
- закрыть меню во время pending purchase: server transaction завершается, а повторное открытие refresh-ит текущую или предыдущую доступную страницу;
- выполнить Reset Character 5 раз: plot/spawn/office сохраняются, HUD button и connections не дублируются;
- injected failure template: pending root исчезает, old visual остаётся, Cash/layout не меняются, orphan root отсутствует;
- destroy/rebuild round-trip воспроизводит те же IDs, versions, placement keys и transforms;
- выйти и зайти на тот же живой server до TTL: временный snapshot восстанавливается; после TTL/перезапуска server восстановление не гарантируется;
- проверить tier transition и equipment L2/L3 replacement: после завершения существует ровно один `OfficeBuildRoot` и одна active model на slot;
- пройти весь catalog: старт 250000, total debit 205150, final Cash 44850;
- после полного catalog проверить ровно один `SpawnLocation`, `PlotAnchor`, `OfficeBuildRoot` и `EntranceApproach`, а также отсутствие project errors в Output;
- **Start Server + 3 Players:** каждый видит replicated офисы, но purchase меняет только authoritative plot отправителя;
- через test probe попытаться изменить чужой office/передать чужой plotId — сервер отклоняет, ownership maps и обе модели неизменны;
- проверить все крайние tier anchors и maximum-content Global HQ: ни один `BasePart` не выходит за plot boundary, doorway/spawn/entrance path свободны;
- в Script Profiler/MicroProfiler измерить initial Garage, full layout и 10 rebuilds; записать worst-case duration/Instance count и убедиться в отсутствии длительного роста memory.

Для Stage 4 `rejoin` означает только same-server snapshot с TTL либо deterministic destroy/rebuild. Это не проверка DataStore и не доказательство cross-server persistence.

### Employees

- каждая роль;
- недостаточно денег;
- занятый desk;
- удалённый desk;
- перекрытый маршрут;
- новый office tier;
- увольнение;
- выход во время движения.

### Product

- запуск без команды;
- минимальная команда;
- полная команда;
- отмена;
- ранний release;
- обычный release;
- повторный release;
- максимум bugs;
- максимум quality;
- sunset.

### Economy

- массовые покупки;
- payroll при нулевом Cash;
- offline;
- boost expiry;
- prestige;
- concurrent requests;
- leaderboard после premium boost.

### Saves

- обычный выход;
- закрытие клиента;
- быстрый rejoin;
- выключение server;
- старая схема;
- пустой профиль;
- отсутствующие поля;
- долгий офлайн;
- client clock manipulation.

### UI

- 1366×768;
- 1920×1080;
- маленький mobile;
- большой mobile;
- touch;
- keyboard/mouse;
- gamepad;
- несколько modals;
- respawn;
- rejoin во время tutorial.

### Monetization

- cancel;
- success;
- receipt retry;
- disconnect;
- repeat consumable;
- pass already owned;
- subscription active/inactive;
- API failure.

## 7. Security tests без exploit-инструментов

Через тестовые LocalScripts/Command Bar попытаться:

- отрицательная цена;
- очень большое число;
- неизвестный ID;
- чужой plot ID;
- request в неверном состоянии;
- 50–100 remote calls;
- повтор transactionId;
- client timestamp;
- двойной reward claim.

Ожидание: сервер отклоняет запрос, не меняет состояние и при необходимости пишет SECURITY warning.

## 8. Performance

### Script Profiler

Проверить NPC update, economy tick, UI selectors, product progress, save serialization.

### MicroProfiler

Искать spikes, тяжёлую генерацию, pathfinding bursts и массовое instance creation.

### Soak

Минимум 30 минут: строить, нанимать, выпускать, открывать UI, менять комнаты. Memory не должна постоянно расти.

## 9. UX-тест

Дать игру человеку без инструкции. Наблюдать, понимает ли он первую цель, найм, роли, progress, результат релиза и следующий шаг. Не подсказывать.

## 10. Переход дальше

Разрешён, если:

- acceptance выполнен;
- blocker/critical = 0;
- major = 0 либо явно одобрены;
- regression зелёный;
- есть commit/tag;
- checklist обновлён.
