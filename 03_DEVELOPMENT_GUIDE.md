# Startup Studio Tycoon — Development Guide

## 1. Архитектурные принципы

1. Сервер является единственным источником истины для валют, покупок, найма, производительности, релизов, квестов, сохранений, prestige и monetization grants.
2. Клиент отвечает за отображение, input, локальные анимации, камеру и feedback.
3. Конфиги отделяются от логики.
4. Бизнес-логика оформляется чистыми функциями, где это возможно.
5. Зависимости сервисов явные.
6. Побочные эффекты не скрываются в `require`.
7. Любая экономическая операция имеет reason/source tag.
8. Повторяемые внешние операции проектируются идемпотентно.

## 2. Структура

```text
src/
├─ ReplicatedStorage/
│  ├─ Shared/
│  │  ├─ Config/
│  │  ├─ Constants/
│  │  ├─ Types/
│  │  ├─ Utils/
│  │  ├─ Domain/
│  │  └─ Packages/
│  └─ Remotes/
├─ ServerScriptService/
│  ├─ Bootstrap/
│  ├─ Services/
│  ├─ Systems/
│  ├─ Security/
│  └─ Analytics/
├─ ServerStorage/
│  ├─ NPCTemplates/
│  ├─ RoomTemplates/
│  └─ Assets/
├─ StarterPlayer/
│  └─ StarterPlayerScripts/
│     ├─ Bootstrap/
│     ├─ Controllers/
│     ├─ UI/
│     └─ Input/
├─ StarterGui/
└─ Workspace/
   └─ Map/
tests/
├─ unit/
├─ integration/
└─ fixtures/
```

## 3. Naming

- ModuleScript: `PascalCase.lua`.
- Server script: `Name.server.lua`.
- Client script: `Name.client.lua`.
- Service: `SomethingService`.
- Controller: `SomethingController`.
- Config: `SomethingConfig`.
- Event: свершившееся событие, например `ProductReleased`.
- Request: намерение, например `RequestHireEmployee`.
- Boolean: `is`, `has`, `can`, `should`.
- ID: строка с устойчивым префиксом.
- Не использовать абстрактные `data`, `info`, `manager`, `handler` без контекста.

## 4. Luau standards

Production-модули:

```lua
--!strict
```

Правила:

- экспортировать типы;
- избегать `any`;
- использовать guard clauses;
- явно обрабатывать `nil`;
- не использовать глобальные переменные;
- не изменять входные таблицы без контракта;
- избегать больших модулей;
- не использовать `wait()`;
- отключать event connections;
- не хранить Player/Instance в save data;
- не делать yield внутри критической транзакции без анализа.

## 5. Service lifecycle

```lua
export type Service = {
    Init: (self: Service, registry: ServiceRegistry) -> (),
    Start: (self: Service) -> (),
    Destroy: (self: Service) -> (),
}
```

`Init` связывает зависимости. `Start` подключает события. `Destroy` очищает connections, задачи и player-specific state.

## 6. Remotes

- remotes создаются централизованно;
- клиент не передаёт итоговую цену, награду или productivity;
- сервер принимает намерение и ID;
- сервер повторно вычисляет стоимость;
- payload проверяется по типу, длине и диапазону;
- частые remotes имеют rate limit;
- RemoteFunction не используется для долгих операций;
- чувствительные данные не находятся в ReplicatedStorage.

Безопасный hire flow:

1. проверить тип `candidateId`;
2. найти candidate в server-side session;
3. проверить expiry;
4. вычислить цену;
5. проверить баланс;
6. атомарно списать Cash;
7. создать сотрудника;
8. отправить результат.

## 7. Экономические транзакции

Единый API:

```text
Credit(playerId, currency, amount, reason, transactionId)
Debit(playerId, currency, amount, reason, transactionId)
```

Требования:

- amount > 0;
- валюта известна;
- transactionId уникален для повторяемых операций;
- feature-модули не меняют баланс напрямую;
- каждая операция имеет reason;
- premium и крупные операции логируются;
- отрицательный баланс запрещён.

## 8. Конфиги

В конфиги выносятся:

- цены;
- таймеры;
- multipliers;
- progression curves;
- product definitions;
- employee roles;
- research tree;
- monetization IDs;
- quests;
- events;
- feature flags;
- performance limits.

Startup validation:

- уникальные ID;
- нет циклов prerequisite graph;
- положительные цены;
- корректные диапазоны;
- все ссылки существуют.

## 9. Save architecture

```lua
export type PlayerProfile = {
    schemaVersion: number,
    currencies: {
        cash: number,
        gems: number,
        reputation: number,
        founderPoints: number,
    },
    office: {
        tier: number,
        rooms: {string},
        upgrades: {[string]: number},
        themeId: string,
    },
    employees: {EmployeeSaveData},
    products: {ProductSaveData},
    research: {[string]: number},
    automation: {[string]: boolean},
    quests: QuestSaveData,
    tutorial: TutorialSaveData,
    entitlements: EntitlementSaveData,
    timestamps: {
        createdAt: number,
        lastSeenAt: number,
        lastSaveAt: number,
    },
}
```

Правила:

- `schemaVersion` обязателен;
- миграции последовательны;
- defaults reconcile;
- клиентские таблицы не сохраняются напрямую;
- сохраняются ID и числа;
- autosave использует jitter;
- важные milestones инициируют save;
- shutdown handling ограничен по времени;
- ошибки видимы в логах.

## 10. Offline progression

- время server-side;
- elapsed clamp;
- max window в config;
- учитываются стабильные revenue streams;
- временные boosts не продлеваются автоматически;
- результат показывается игроку;
- повторный claim запрещён.

## 11. NPC

State machine:

```text
Spawn → Idle → MoveToDesk → Work → Break → Work
                    ↘ Recover
```

Требования:

- ограничение пересчёта path;
- timeout waypoint;
- stuck detector;
- fallback только внутри своего plot;
- productivity не зависит от анимации;
- упрощение визуала на расстоянии;
- batching при нагрузке.

## 12. Product system

Разделение:

- `ProductDefinitions`;
- `ProductStateMachine`;
- `ProductProgressCalculator`;
- `ReleaseScoreCalculator`;
- `RevenueCalculator`;
- `ProductLifecycleService`;
- `ProductService`.

Calculators имеют unit tests. State machine запрещает нелегальные переходы.

## 13. UI

Слои:

1. `UIRoot`.
2. `UIStore`.
3. `Controllers`.
4. `Views`.
5. `Presenters/Selectors`.

Правила:

- UI не меняет authoritative currency;
- подписки не дублируются;
- modal stack;
- responsive constraints;
- mobile safe zones;
- gamepad focus;
- единые notifications;
- форматирование чисел централизовано.

## 14. Monetization

### Developer Products

- receipt на сервере;
- grant идемпотентен;
- неизвестный ID не подтверждается;
- pending переживает rejoin;
- analytics не заменяет grant.

### Game Passes

- ownership server-side;
- benefits применяются при загрузке и покупке.

### Subscription

- статус через штатный API;
- награда имеет server timestamp;
- один период нельзя получить дважды.

## 15. Logging

Уровни:

- DEBUG;
- INFO;
- WARN;
- ERROR;
- SECURITY;
- ECONOMY;
- PURCHASE.

Поля: timestamp, environment, server job id, userId, subsystem, event, безопасные metadata. Не логировать секреты и полный профиль.

## 16. Errors

- `assert` только для programmer errors/startup invariants;
- user requests возвращают безопасный error result;
- внешние сервисы через `pcall`;
- retry имеет limit/backoff;
- ошибка визуала не откатывает подтверждённую транзакцию;
- feature можно выключить flag-ом.

## 17. Security checklist

- validate type;
- validate range;
- validate ownership;
- validate state transition;
- validate cooldown;
- recompute price;
- ignore client timestamps;
- rate-limit spam;
- no arbitrary instance paths;
- no client-selected reward;
- no client-confirmed receipt.

## 18. Performance

- лимит активных NPC;
- не делать тяжёлый цикл каждый frame;
- batch economy ticks;
- избегать частого `GetDescendants()`;
- delta updates вместо полного профиля;
- не пересоздавать UI;
- не генерировать декор повторно;
- тестировать target max players.

## 19. Tests

### Unit

- calculators;
- configs;
- migrations;
- serialization;
- curves;
- quests;
- idempotency.

### Integration

- bootstrap;
- remote request;
- hire;
- build;
- release;
- save/load;
- receipt grant.

### Manual

По `05_MANUAL_QA_GUIDE.md`.

## 20. Definition of Done feature

- scope реализован;
- границы соблюдены;
- config валиден;
- format/lint/tests/build успешны;
- Studio smoke и regression успешны;
- blocker/critical отсутствуют;
- документация обновлена;
- diff просмотрен человеком.
