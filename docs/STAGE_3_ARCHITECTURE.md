# Stage 3 — Player session, plot ownership and office shell

## Границы

Stage 3 создаёт только session-scoped plots, стартовую оболочку офиса, spawn/respawn и server-side ownership validation. Покупки комнат, мебель, апгрейды, экономика, DataStore, сотрудники, продукты, UI, monetization и заготовки Stage 4 отсутствуют.

Plot domain находится только в `ServerScriptService` и `ServerStorage`. В `ReplicatedStorage` не публикуются `PlotTypes`, `PlotBounds`, `PlotDefinitions` или authoritative ownership API. Save schema не меняется: назначение plot живёт только в текущем сервере.

## Конфигурация

`ServerStorage.Config.PlotDefinitions` задаёт:

- `maxPlayers = 6`;
- шесть definitions `plot_01` … `plot_06` в стабильном порядке allocation;
- сетку 3 × 2;
- footprint 96 × 96 studs;
- ground-level `origin` в центре поверхности;
- вертикальный диапазон от 0 до `maxHeight = 64`;
- center spacing 128 studs и минимальный gap 32 studs.

`PlotConfigValidator` проверяет типы, конечность чисел/transforms, уникальность ID, capacity, spawn и office bounds, а также пересечения с требуемым gap. После проверки `ConfigLoader` копирует и рекурсивно замораживает конфиг.

`PlotBounds` работает в local space definition. Y измеряется относительно ground-level origin и не центрируется вокруг него. Definitions могут быть повёрнуты вокруг Y; point, box и footprint-overlap проверки не зависят от world axes.

## Lifecycle и DataModel

`PlotService` и `PlayerSessionService` регистрируются в принятом Stage 2 `ServiceRegistry`. `PlayerSessionService` имеет явную dependency на `PlotService`. `require` не создаёт Instances, connections или задачи.

Canonical `Workspace.Map.Plots` создаётся идемпотентно в `PlotService:Init()`. Это единственный выбранный способ runtime-создания контейнера; `.gitkeep` не используется как доказательство DataModel mapping. Collision с Instance неправильного класса является startup error.

`PlayerSessionService:Start()` сначала подключает `PlayerAdded`/`PlayerRemoving`, затем обрабатывает уже присутствующих игроков через idempotent `BeginSession`. На игрока существует не более одной `CharacterAdded` connection. Все connections и sessions очищаются в `Destroy`.

## Ownership и allocation transaction

Authoritative state находится только в серверных maps:

```text
userId → plotId
plotId → userId
plotId → allocation { userId, state, generationToken, model }
```

Публичные Attributes являются только отображением:

- `Player.AssignedPlotId`;
- runtime plot model `PlotId`;
- runtime plot model `OwnerUserId`.

`AllocationState` не реплицируется. Сервер никогда не читает Attributes для решения об ownership.

Allocation выполняется синхронно без yield:

```text
find first free definition
→ reserve both ownership maps
→ build an unparented model
→ validate every generated BasePart against bounds
→ recheck reservation/token
→ commit model to Workspace.Map.Plots
→ mark allocation Active
```

Plot считается занятым сразу после двустороннего reserve, до generation. Поэтому следующий `PlayerAdded` не может выбрать тот же ID. Builder production-кода синхронный и non-yielding; generation token является только лёгкой защитой stale commit и не создаёт asynchronous subsystem.

Повторный `AssignPlayer` для уже назначенного userId возвращает текущее allocation и не создаёт вторую модель. Первый свободный plot всегда выбирается в порядке definitions.

## Starter office shell

`OfficeShellBuilder` детерминированно создаёт anchored runtime model:

- floor 48 × 36 studs;
- back и side walls;
- два front wall segments с широким входом;
- wall height 14;
- wall thickness 1;
- floor thickness 1;
- нейтральную физическую spawn platform и marker перед входом, внутри plot и лицом к офису;
- низкую нейтральную boundary frame.

Крыша, мебель, purchase pads, upgrade buttons и Stage 4 anchors отсутствуют. Builder сначала создаёт unparented model. При исключении он уничтожает частичную модель и возвращает typed failure.

## Failure, leave и idempotent cleanup

При build/validation/collision failure `PlotService` снимает обе ownership-записи и уничтожает uncommitted model. `PlayerRemoving` вызывает тот же `ReleasePlayer`.

Release:

1. является success/no-op при отсутствии allocation;
2. инвалидирует generation token;
3. снимает прямую и обратную ownership-запись;
4. уничтожает runtime model по server-owned reference;
5. удаляет allocation;
6. позволяет следующему игроку снова получить освободившийся ID.

Повторный release безопасен. Production startup orphan cleaner отсутствует. `ValidateRuntimeState` выполняет bounded test/debug validation maps и `Workspace.Map.Plots`; runtime specs вызывают его после failure, release и Destroy.

Если свободных plots нет, сервер пишет `plot_capacity_exhausted`, не создаёт model и не назначает чужой участок. `PlayerSessionService` выполняет безопасный kick с текстом `Unable to prepare your office plot. Please rejoin.`. Waiting queue отсутствует.

## Spawn и respawn

Roblox automatic character spawning остаётся включённым. Production-код не вызывает `LoadCharacter`.

`OfficeShellBuilder` создаёт физическую площадку как `SpawnLocation`, а не как обычный `Part`. После active allocation сервер получает spawn только через authoritative `PlotService`, сверяет generation token и устанавливает `Player.RespawnLocation`. При release ссылка очищается до уничтожения runtime model. `RespawnLocation` направляет automatic engine spawn, но не заменяет ownership validation.

Session service подключает ровно один `CharacterAdded` и один `CharacterAppearanceLoaded` на игрока. `CharacterAdded` фиксирует актуальный character, а финальный защитный `PivotTo` выполняется после lifecycle-сигнала `CharacterAppearanceLoaded`; уже загруженный character обрабатывается через `HasAppearanceLoaded`. `HumanoidRootPart` ищется с timeout 10 секунд. После возможного yield повторно проверяются:

- активная session принадлежит тому же Player;
- `player.Character` всё ещё равен обрабатываемому character;
- character остаётся pending character текущей session;
- обе authoritative ownership-записи совпадают;
- allocation остаётся `Active`;
- plot ID, generation token и `SpawnLocation` совпадают с session.

Только после проверок сервер выполняет `character:PivotTo`. Произвольные задержки, retry loops, `Touched` и постоянные per-frame loops не используются. Plot ID, owner и transform от клиента не принимаются. Диагностика spawn lifecycle (`userId`, plot ID, generation token, expected/before/after position, current-character flag и physical spawn class) включена только в Studio/Test environment; production output не получает эти информационные события.

## Ownership API и remotes

`PlotService` предоставляет server-only методы чтения ownership, `RequireOwnership`, spawn lookup и debug/test invariant validation. Любой будущий mutation должен сначала получить успешный `RequireOwnership(userId, plotId)`. Attributes не заменяют этот вызов.

Production `RemoteDefinitions` остаётся пустым: join, allocation, shell replication и spawn не требуют remote. `test.project.json` отдельно отображает `TestPlotMutation` и foreign ownership probe. Probe проверяет owner success и `PlotOwnershipMismatch` без mutation для другого клиента. Он отсутствует в production sourcemap/build.

## Проверки

Structural suite `scripts/Test-Stage3.ps1` проверяет пути, server-only placement, approved config constants, production/test mapping separation, отсутствие production remote и production/test sourcemaps. Он не заявляет, что доказал concurrency, rollback или multiplayer behavior.

Studio runtime harness проверяет config/bounds, rotated geometry, unique/idempotent allocation, capacity, release/double release/reuse, три различных spawn transform, deterministic shell со `SpawnLocation`, ownership rejection, failure rollback, orphan detection, production initial spawn и respawn, stale character rejection, очистку/rebinding `RespawnLocation` и отсутствие duplicate plot model после respawn. Existing Stage 2 client test продолжает доказывать production client bootstrap.

Фактические simultaneous join, Start Server + 3 Players, leave/rejoin и test-only foreign remote требуют ручного запуска Roblox Studio.
