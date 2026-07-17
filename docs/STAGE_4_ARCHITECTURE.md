# Stage 4 — Server-authoritative office building

## Scope and ownership

Stage 4 implements session-scoped room, equipment, furniture, upgrade and office-tier purchases. It does not add DataStore, ProfileService, autosave, income, employees, NPCs, products, prestige, monetization or a general UI framework.

The runtime ownership boundary is fixed:

```text
PlotRuntimeModel                         PlotService ownership
├─ PlotAnchor                           stable PrimaryPart
├─ PlotBoundary
├─ SpawnLocation
├─ SpawnMarker
└─ OfficeBuildRoot                      OfficeBuildingService ownership
   ├─ TierShell
   │  └─ EntranceApproach               replaceable tier-local walkable bridge
   ├─ Rooms
   ├─ Equipment
   └─ Furniture
```

`PlotRuntimeBuilder` replaces the Stage 3 `OfficeShellBuilder`. It builds only `PlotAnchor`, boundary, spawn and marker. `PlotAnchor` is invisible, anchored, non-collidable/non-queryable and remains `PlotRuntimeModel.PrimaryPart` for the allocation lifetime. It is never supplied by a tier template. `OfficeBuildingService:PrepareSession` creates the authoritative Garage root after plot allocation and currency-session open. There is one Garage floor/wall set; Stage 3 spawn and boundary remain untouched.

`OfficeBuildingService` cannot destroy the plot root, create a spawn/anchor, change `Player.RespawnLocation`, mutate plot ownership maps or generation tokens. Only `PlayerSessionService` owns `PlayerAdded`, `PlayerRemoving`, character and respawn connections.

## Authoritative data

`OfficeLayoutState` contains data only:

```luau
{
    schemaVersion: number,
    configVersion: number,
    officeTierId: string,
    purchasedRooms: {[string]: boolean},
    purchasedEquipment: {[string]: boolean},
    purchasedFurniture: {[string]: boolean},
    upgradeLevels: {[string]: number},
    occupiedSlots: {[string]: {itemId: string, placementKey: string}},
    placementKeys: {[string]: string},
    revision: number,
}
```

It never stores `Instance`, `Player`, `Model` or client `CFrame`. The client sends only a bounded `requestId`, selected category/page or `itemId`. Plot, owner, price, balance, tier, prerequisites, slot, anchor, placement and result are derived by the server.

The initial `tier_garage` is price 0 and starts `Purchased`; it is not purchasable again. Every other tier, room, equipment, furniture and upgrade step has an integer price greater than zero. The complete catalog costs 205150.

## Services and domain contracts

- `OfficeCatalog.new(config, progression) -> Catalog`
  - `GetCategoryCounts() -> {[OfficeCategoryId]: number}`
  - `GetItem(layout, itemId, isPending) -> Result<OfficeCatalogItem>`
  - `GetPage(layout, cash, categoryId, page, pendingItems) -> Result<OfficeCatalogPage>`
- `OfficeProgression.new(config) -> Progression`
  - `CreateInitialLayout() -> OfficeLayoutState`
  - `Evaluate(layout, itemId, isPending) -> Result<Evaluation>`
  - definition lookups are read-only and server-side.
- `OfficePlacement.new(progression) -> Placement`
  - `ResolveRoom(tierId, roomId, plotOrigin) -> Result<ResolvedEnvelope>`
  - `ResolveItem(tierId, itemId, plotOrigin) -> Result<ResolvedEnvelope>`
  - `ResolveLayout(tierId, layout, plotOrigin, spawnCFrame) -> Result<{ResolvedEnvelope}>`
- `OfficeGeometryValidator`
  - `ValidateLayout(plotDefinition, envelopes) -> Result<true>`
  - `ValidateRuntimeModel(plotDefinition, model) -> Result<true>`
  - checks room-room and item-item overlap, item-room containment, doorway, spawn and entrance clearance plus `PlotBounds`.
- `OfficeLayoutBuilder.new(templates, config, progression, placement, hook?) -> Builder`
  - `BuildReplacementRoot(plotContext, layout) -> Result<Model>`
  - builds an unparented full replacement root and destroys it on every failure.
- `OfficeBuildingService`
  - lifecycle `Init(dependencies)`, `Start()`, `Destroy()`;
  - `PrepareSession(userId, restoredLayout?) -> Result<OfficeLayoutState>`;
  - `GetCatalogPage(userId, request) -> OfficeCatalogResponse`, whose domain operation is `GetCatalogPage(userId, categoryId, page) -> Result<OfficeCatalogPage>`;
  - `Purchase(userId, request) -> OfficePurchaseResponse`;
  - `StopPurchases`, `ExportLayout`, `CloseSession`, `AbortSession`, `ValidateRuntimeState`.
- `SessionCurrencyService`
	- replaceable Stage 4 `Cash` interface: open/restore/export/close, get balance, reserve/commit/release/compensate debit;
  - it is session funding, not the Stage 8 economy ledger.
- `OfficeSnapshotCache.new(clock, ttlSeconds, capacity) -> Cache`
  - `Put`, `Peek`, `Consume`, `Remove`, `EvictExpired`, `GetCount`, `Destroy`;
  - uses an injected monotonic clock and lazy bounded eviction; it has no heartbeat loop.

All modules are side-effect free during `require`. Services keep accepted `Init/Start/Destroy` lifecycle and deterministic registration order.

## Join, leave and failure orchestration

Join order is synchronous until character observation:

```text
allocate PlotRuntimeModel
→ open or restore Currency session
→ prepare or restore OfficeBuildRoot (Garage for a fresh session)
→ resolve authoritative SpawnLocation
→ install character connections
→ set RespawnLocation and readiness attributes
```

If currency open fails, the plot is released. If office preparation/restore fails, pending office is destroyed, office and currency sessions are aborted, `RespawnLocation` is cleared, the plot is released through existing Stage 3 APIs and the snapshot remains cached until TTL. If spawn resolution fails, the same rollback runs. No occupied plot or orphan model remains.

Leave order is:

```text
disconnect character observers and clear readiness/RespawnLocation
→ stop new office purchases
→ export data-only layout and currency snapshots
→ put bounded in-memory snapshot
→ close office and currency sessions
→ release plot through PlotService
```

Neither currency, office nor snapshot cache owns player lifecycle connections.

## Purchase transaction

The non-yielding critical path is:

1. validate the remote payload and rate limit;
2. resolve the active office session and authoritative player plot;
3. resolve config and server price;
4. validate tier, prerequisite graph, duplicate purchase and slot occupancy;
5. resolve deterministic anchors, validate geometry and plot bounds;
6. check authoritative Cash and reserve an idempotent debit;
7. copy layout data and build a complete unparented replacement root;
8. commit the debit while the old canonical visual remains active;
9. atomically publish one new canonical root/layout and destroy the old root;
10. clear pending state, cache the bounded response and return authoritative Cash/revision/state.

The per-user `activeRequestId` admits only one mutation. `pendingItems` produces `Pending` catalog state. A 64-entry bounded request cache maps `requestId` to a request signature and response. The same ID/signature returns the same response; the same ID with different item or category/page returns `RequestIdConflict`. There is no yield between guard, reservation, build, commit and state swap.

Generation, placement, ownership or debit failure releases the reservation, destroys the pending root and retains old layout/visual. Debit-commit failure does the same. A publication failure compensates the committed debit before restoring old state. Cleanup failures are logged and `ValidateRuntimeState` rejects temporary or multiple roots. After every completed transaction the plot has exactly one child named `OfficeBuildRoot`.

## Remote API

Production contains exactly two `RemoteFunction`s registered by the centralized Stage 2 registry.

`RequestOfficeCatalog` request:

```luau
{requestId: string, categoryId: "Tiers" | "Rooms" | "Equipment" | "Furniture" | "Upgrades", page: number}
```

Response:

```luau
{
    ok: boolean, requestId: string, categoryId: OfficeCategoryId,
    page: number, pageCount: number, totalItems: number,
    revision: number, currentTierId: string, cash: number,
    items: {OfficeCatalogItem}, error: OfficeRemoteError?,
}
```

`RequestOfficePurchase` request is `{requestId: string, itemId: string}`. Its response includes `ok`, echoed IDs, authoritative `revision`, `currentTierId`, `cash`, `state`, optional `currentLevel` and safe `error`.

Purchase state is one enum: `Available | Purchased | Locked | MaxLevel | Pending`. Rooms/equipment/furniture become `Purchased`. An L2 upgrade with L3 available returns `Available`; L3 returns `MaxLevel`. A prerequisite failure is `Locked`. Insufficient funds leaves an otherwise purchasable item `Available`.

The safe client error catalog is: `InvalidPayload`, `RateLimited`, `RequestIdConflict`, `PurchaseInProgress`, `OfficeSessionNotReady`, `UnknownOfficeItem`, `InvalidOfficeCategory`, `InvalidCatalogPage`, `InsufficientFunds`, `ItemAlreadyPurchased`, `InitialTierAlreadyOwned`, `OfficeTierLocked`, `PrerequisiteMissing`, `RequiredRoomMissing`, `EquipmentSlotOccupied`, `UpgradeTargetMissing`, `UpgradeMaxLevel`, `OfficeBoundsViolation`, `OfficeBuildFailed`, `TransactionFailed`, `InternalError`. Internal template, geometry, generation, stale-token and currency errors are mapped into those codes without exposing paths, traces or server details.

Rate limits are token buckets per player/action: catalog 4 burst with 1 token/second; purchase 6 burst with 2 tokens/second. Payload strings, records, arrays, numbers and unknown keys are bounded by `PayloadValidator`.

## Pagination and payload budget

Page size is 5. Sort order is the validated config `sortOrder`/stable config order. Counts and pages are:

| Category | Items | Pages |
|---|---:|---:|
| Tiers | 5 | 1 |
| Rooms | 9 | 2 |
| Equipment | 9 | 2 |
| Furniture | 9 | 2 |
| Upgrades | 9 | 2 |

Pagination occurs only inside the selected category. For a non-empty category, out-of-range pages return `InvalidCatalogPage`, actual category `pageCount`/`totalItems` and empty `items`. An empty category accepts page 1 with pageCount 0. After purchase the client refreshes the current page; if it is invalid/empty it falls back one page at a time.

The theoretical largest valid response is bounded at 109 validator nodes and depth 4: root plus 11 possible response fields, five item records with all 14 fields and four prerequisite IDs, including an optional error object. The shared defaults remain 128 nodes/depth 8, so the 41-item catalog requires no limit increase because only five items cross the remote per page. Six response items are rejected.

## Placement, templates and reconstruction

Every tier provides a complete deterministic `roomAnchors` map. Room, equipment and furniture placement is reconstructed as `plotOrigin * tierAnchor * serverSlotOffset * envelopeOffset`; world-space client transforms never enter state. Tier shell parts use `plotOrigin * CFrame.new(localOffset)` so rotated plots retain orientation.

Every tier shell also owns exactly one collidable `EntranceApproach`. `OfficeEntranceGeometry.Resolve` derives its 8-stud width, local-Z span, complete clearance envelope and spawn clearance from the tier floor edge and the existing PlotService-owned `SpawnLocation`. `OfficeLayoutBuilder` and `OfficePlacement` consume that same result, so overlap validation covers the exact physical route for all tiers and rotated plots. The approach touches both surfaces at the same top height without overlapping the spawn. It is rebuilt with `OfficeBuildRoot`, while `SpawnLocation`, `Player.RespawnLocation` and the stable `PlotAnchor` remain outside Stage 4 replacement ownership.

All 50 production templates are server-only under `ServerStorage.OfficeTemplates`: 5 tier models, 9 room models, 27 equipment L1/L2/L3 models and 9 furniture models. Each has an anchored, invisible `Pivot`, category-specific production detail and no scripts/remotes/prompts. Tier templates contain at least six visible architectural parts, room and furniture templates at least five purpose-specific parts, and equipment L1/L2/L3 at least four/five/six structurally different parts. Runtime validation proves every template is catalog-reachable, unique and contained by its authoritative shell/room/item envelope. `OfficeLayoutBuilder` creates only common technical shell/floor/approach geometry; equipment, furniture and room identity is template-owned.

`OfficeLayoutSerializer` copies and validates the data-only layout. Runtime specs exercise destroy/rebuild round-trip and a same-server snapshot restore path. Snapshot TTL is 15 minutes and capacity is 24. A server restart, cross-server transfer, TTL expiry or eviction loses this temporary snapshot; Stage 4 makes no persistence claim. Stage 9 will replace it with a persistent profile contract.

## Funding and UI

`initialCashByEnvironment` explicitly configures Development, Test and Production to 250000. Production never inherits a Development/Test fallback. This is provisional Stage 4 session funding so all building paths are testable without an income source. Stage 8 replaces the funding source through the currency interface.

The Stage 4 client is a minimal menu: persistent HUD Build button, optional `B` shortcut, five category tabs, prices, server states/errors and pagination. It is disabled until `OfficeSessionReady`; closing it never cancels a server transaction. Catalog and purchase invocations use protected calls and safe retryable errors. Catalog generations reject stale out-of-order pages, purchase pending state clears after both response and exception, and destroyed views invalidate pending callbacks. The controller and view are initialized once by the client lifecycle, so respawn does not duplicate buttons or connections.

## Verification boundary

Unit/runtime specs cover config, progression, pagination, template reachability/content, placement, exact entrance geometry, serialization, currency, snapshots, rate limits, purchases, rollback, reconstruction, same-server rejoin, remotes, client invocation exceptions/stale responses, multiplayer ownership, maximum layout, production runtime and full catalog funding. `scripts/Test-Stage4.ps1` verifies files, category-specific template minima, generic-decorator removal, isolation and sourcemaps.

Rojo build, format, lint and structural tests do not execute Roblox physics, replication, multiplayer UI or profiler measurements. Solo and Start Server + 3 Players scenarios in `05_MANUAL_QA_GUIDE.md` remain a required Studio acceptance gate.
