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

### Plot

- два игрока входят одновременно;
- третий входит позже;
- владелец выходит;
- новый игрок получает свободный plot;
- клиент пытается изменить чужой plot.

### Building

- недостаточно Cash;
- ровно достаточно Cash;
- двойной клик;
- spam;
- prerequisite;
- следующая комната;
- выход сразу после покупки;
- rejoin.

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
