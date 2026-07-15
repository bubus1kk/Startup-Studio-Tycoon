# Stage 2 — Architecture foundation and contracts

## Границы

Stage 2 реализует только инфраструктурный каркас. Сервер остаётся authoritative. Gameplay-сервисы, реальные игровые remotes, DataStore, save schema, экономика, monetization и Stage 3 отсутствуют.

`require` модулей не создаёт Instances, connections или фоновые задачи. Runtime side effects начинаются только в lifecycle `Init`/`Start` из server/client composition root.

## Lifecycle и зависимости

`Shared.Infrastructure.LifecycleRegistry` — единственная реализация:

- dependency resolution;
- cycle detection;
- deterministic topological ordering;
- `InitAll`, `StartAll`, `DestroyAll`;
- rollback и cleanup diagnostics.

`ServiceRegistry` и `ControllerRegistry` являются только server/client именами этого generic engine и не дублируют алгоритмы.

Registration definition содержит стабильное имя, явные dependency names, публикуемое через resolver значение и hooks `Init`, `Start`, `Destroy`. Resolver позволяет получить только объявленную зависимость.

Независимые узлы сортируются по имени. Один вычисленный порядок используется для `Init` и `Start`; `Destroy` выполняется в обратном порядке.

Rollback semantics:

- при ошибке `Init` уничтожаются только объекты, чей `Init` завершился успешно;
- при ошибке `Start` уничтожаются все успешно инициализированные объекты;
- cleanup идёт в обратном startup order;
- ошибка одного `Destroy` диагностируется как `LifecycleCleanupFailed` и не останавливает остальные;
- `DestroyAll` идемпотентен.

## Remote contracts

Shared слой:

- `RemoteDefinitions` — production-список; на Stage 2 он пуст;
- `RemoteTypes` — безопасные публичные типы;
- `RemoteDefinitionValidator` — проверка names, kinds, directions и validators;
- `PayloadValidator` — bounded type/range/length/depth/collection validation.

Server слой:

- `ServerRemoteRegistry` единолично создаёт `RemoteEvent` и `RemoteFunction`;
- duplicate definition и Instance name collision отклоняются;
- client-to-server bindings всегда оборачиваются request validator;
- invalid payload не достигает callback и создаёт безопасный `SECURITY` log;
- `RemoteFunction` возвращает безопасную ошибку и не предназначен для долгих операций.

Client слой:

- `RemoteClient` только ожидает и проверяет заранее созданные server Instances;
- клиент никогда не создаёт и не уничтожает remotes.

Test-only definitions находятся в `tests/fixtures` и отображаются только `test.project.json`. `default.project.json` не отображает tests или `TestSupport`.

## Config, environment и flags

Config pipeline:

1. получить явный config module;
2. проверить типы, обязательные поля, enum и unknown keys;
3. скопировать проверенное значение;
4. рекурсивно выполнить `table.freeze` для корня и всех вложенных таблиц;
5. публиковать только замороженную копию.

Freeze является recursive, не shallow. Исходная mutable таблица не публикуется.

`ServerConfig` находится в `ServerStorage`. Environment имеет значения `Studio`, `Test`, `Production`; `Auto` выбирает `Studio` через `RunService:IsStudio()`, иначе `Production`. `Test` задаётся только server-side config. Public и server debug flags разделены и фактически управляют уровнем Logger.

## Bootstrap

`ServerApplication` загружает configs, создаёт Logger, ServiceRegistry и ServerRemoteRegistry, затем выполняет lifecycle. Production server bootstrap регистрирует `game:BindToClose` для идемпотентного cleanup.

`ClientApplication` использует тот же lifecycle engine для RemoteClient. Он предоставляет явный `Destroy` для тестов и контролируемого teardown. Production client bootstrap не обещает несуществующий client-аналог `BindToClose`.

Runtime-копирование `StarterPlayerScripts` не считается атомарным. До `require` клиент ожидает `Bootstrap.ClientApplication`, `Infrastructure`, `ControllerRegistry` и `RemoteClient` через bounded resolver. Общий deadline каждой startup-операции — 10 секунд. Timeout завершается явным `StartupError` с кодом `StartupDependencyTimeout`; неверный class — `StartupDependencyClassMismatch`. Бесконечный `WaitForChild` и произвольные `task.wait` не используются.

## Автоматические и Studio-проверки

GitHub Actions на `ubuntu-latest` выполняет только:

- `stylua --check src tests`;
- `selene src tests`;
- `scripts/Test-Stage1.ps1`;
- `scripts/Test-Stage2.ps1`;
- production `rojo build`;
- test `rojo build test.project.json`.

В проекте нет исполнимого Luau CLI runner, поэтому CI не выполняет Luau runtime specs. Lune, TestEZ и другие frameworks не добавлены.

`test.project.json` содержит маленький project-local runtime harness. Он автоматически выполняет assertions после ручного запуска test place в Roblox Studio с клиентом, но такой запуск считается ручной Studio-проверкой, а не CI. Финальный `PASS all ... runtime tests` зависит от test client, который сначала подтверждает успешный обычный production bootstrap после события `client_bootstrap_ready`; отдельные server tests больше не могут скрыть падение `ClientApplication`.
