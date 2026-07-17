# Stage 4 — Automated Roblox Studio acceptance

## Purpose and safety boundary

The Stage 4 Acceptance Plugin is a local Roblox Studio plugin that launches the isolated Stage 4 test place through `StudioTestService` and renders the table returned by `EndTest(result)`.

It does not edit or publish a place, use DataStore, install itself, copy files into a user profile, merge Git branches, commit or push. The plugin sources are mapped only by `stage-acceptance-plugin.project.json`. Acceptance server/client code is mapped only by `test.project.json`. `default.project.json` maps neither directory.

The implementation follows Roblox's scripted Studio testing APIs:

- [`StudioTestService`](https://create.roblox.com/docs/reference/engine/classes/StudioTestService) for solo/multiplayer execution, arguments, adding players, client leave and structured completion;
- [`VirtualInput`](https://create.roblox.com/docs/reference/engine/classes/VirtualInput) only as an optional keyboard-input layer;
- [Studio testing modes](https://create.roblox.com/docs/studio/testing-modes) for the scripted-testing and local multi-client model.

## Architecture

```text
local plugin model (never mapped into a place)
└─ StageAcceptancePlugin
   ├─ toolbar + run lock
   ├─ AcceptanceRunner → StudioTestService Execute*Async
   ├─ AcceptanceRunGuard → always restores toolbar buttons
   ├─ AcceptanceTypes → validation/aggregation/formatting
   └─ AcceptanceReportView → dock widget

test place only
├─ ServerScriptService.Stage4Acceptance
│  ├─ Stage4AcceptanceRouter
│  ├─ Stage4SoloAcceptance
│  ├─ Stage4MultiplayerAcceptance
│  ├─ Stage4PerformanceAcceptance
│  └─ AcceptanceTestUtils
└─ StarterPlayerScripts.Stage4AcceptanceClient
   └─ production remote calls, client replication and UI/controller checks
```

The plugin passes serializable arguments. The server router reads them with `GetTestArgs()`, starts one suite, installs that suite's watchdog and calls `EndTest(result)` through `finalizeOnce` exactly once after coordination cleanup. Test-only `RemoteEvent` instances coordinate server and clients inside the running test DataModel; they are not production remotes and are destroyed before completion.

Before and after every `Execute*Async` call, the runner waits (with a 30-second diagnostic timeout) for `StudioTestService.EditModeActive == true`, then requires 0.5 seconds of stable Edit Mode. The polling wait is bounded and the property condition, not an arbitrary delay, controls progress. This barrier prevents the next Full route from starting while Studio is still tearing down the previous session.

The approved production remote registry remains exactly:

- `RequestOfficeCatalog`;
- `RequestOfficePurchase`.

All production catalog purchases made by solo/multiplayer/performance clients use those two contracts. Deterministic destroy/rebuild performance uses the existing server-only `OfficeBuildingService` fixture contract so no debug remote is added to production.

## Suites and toolbar buttons

The toolbar is named **Startup Studio Tests**.

| Button | Studio call | Timeout | Route |
|---|---|---:|---|
| Stage 4 Runtime | `ExecutePlayModeAsync("Stage4RuntimeGate")` | 90 s | existing `TestRunner.server.lua`; real collected Stage 1–4 specs, minimum 57 |
| Stage 4 Solo | `ExecutePlayModeAsync(args)` | 120 s | player/session, full catalog, geometry, five respawns, controller/view tests |
| Stage 4 Multiplayer 3 | `ExecuteMultiplayerTestAsync(3, args)` | 180 s | isolation, Global HQ/Small Loft/Garage, foreign mutation, leave and `AddPlayers(1)` |
| Stage 4 Performance 6 | `ExecuteMultiplayerTestAsync(6, args)` | 240 s | six maximum offices, budgets, ten rebuilds and cleanup |
| Stage 4 Full | the four calls above in order | 480 s orchestration deadline | aggregate report; infrastructure failure or suite watchdog stops later routes |

The Full deadline is checked only between suites; it never interrupts an active `Execute*Async` call. If it expires before another suite starts, the explicit failure is `Full orchestration timeout`. A normally completing final suite is accepted even when the final Full elapsed time exceeds 480 seconds.

Only one run can be active. All buttons are disabled during a run and enabled again after success, nil, timeout or an `xpcall`-captured plugin error. A nil result is always an infrastructure FAIL, never PASS.

`LeaveTest()` is called only by a client after `CanLeaveTest()` succeeds. During Performance6 cleanup, five departing clients leave and the designated last client remains alive until the server calls `EndTest(result)`; the last client therefore cannot close the scripted test session first. `AddPlayers(1)` creates a new simulated client and does not claim to reproduce a real same-UserId reconnect. Same-user snapshot restoration remains the fixed-userId `OfficeRejoinSpec` integration test.

Output lifecycle diagnostics use the `[StageAcceptancePlugin]` prefix and include suite start, configured timeout, Edit Mode state, return elapsed time and result type. A nil/invalid result additionally includes suite elapsed time, Full elapsed time and watchdog state.

## Result contract

Every route returns:

```luau
{
    ok = boolean,
    suite = string,
    total = number,
    passed = number,
    failed = number,
    skipped = number,
    durationSeconds = number,
    failures = {
        { test = string, message = string, traceback = string? },
    },
    metrics = {
        [string] = number | string | boolean,
    },
}
```

The plugin validates types, count consistency, `ok`, failure count and expected suite name. The dock widget and Output show suite, duration, counts, failures, tracebacks and sorted metrics. Status is:

- **FAIL** if any test fails or the returned value is invalid/nil;
- **SKIPPED** when a suite contains no passes and only skipped checks;
- **PASS** when there are no failures (the skipped count remains visible).

If `UserInputService:CreateVirtualInput()` is unavailable or returns nil, only the optional input-level B-key test is SKIPPED. Controller/view tests continue. `VirtualInputManager` is not used.

## Build the plugin and test place

From repository root on branch `stage/04-building`:

```powershell
pwsh -NoProfile -File scripts/Build-StageAcceptancePlugin.ps1
rojo build test.project.json -o build/StartupStudioTycoonStage4Tests.rbxl
```

The first command only writes `build/StageAcceptancePlugin.rbxm`. It does not install the plugin or modify a Studio/system plugin directory.

## Install as a Local Plugin

1. Start Roblox Studio and open a temporary blank place, not the production place.
2. Insert or drag `build/StageAcceptancePlugin.rbxm` into the temporary place.
3. In Explorer, select the top-level `StageAcceptancePlugin` model.
4. Use **Save as Local Plugin** from the model's context menu and confirm the local installation.
5. Remove the inserted model from the temporary place or close that place without saving it.
6. Restart Studio if the **Startup Studio Tests** toolbar does not appear immediately.

Installation is a deliberate Studio action. The repository script never performs it.

## Run acceptance

1. Build both artifacts with the commands above.
2. In Studio, open `build/StartupStudioTycoonStage4Tests.rbxl`. Do not open `build/StartupStudioTycoon.rbxl` for automated acceptance.
3. Clear Output so the run is easy to audit.
4. On **Startup Studio Tests**, click a single suite or **Stage 4 Full**.
5. Leave the Studio test windows open. The plugin controls their lifetime through `EndTest(result)`.
6. Read the dock widget status and counts. For complete diagnostics, read the `[Stage4Acceptance]` and `[StageAcceptancePlugin]` entries in Output.
7. Save the Output log with the tested Git SHA when recording gate evidence.

Do not report Studio runtime PASS from a successful Rojo build alone. PASS requires installing the local plugin, opening the test place and receiving the structured result from a real Studio run.

## Update the local plugin

1. Stop any active Studio test and close the test place.
2. Re-run `pwsh -NoProfile -File scripts/Build-StageAcceptancePlugin.ps1`.
3. In Studio's plugin manager, disable or remove the old local plugin.
4. Repeat **Install as a Local Plugin** with the new `build/StageAcceptancePlugin.rbxm`.
5. Restart Studio and verify the toolbar before running the rebuilt test place.

Rebuilding the `.rbxm` file alone does not replace an already installed local plugin.

## Remove the plugin

1. Open Studio's **Manage Plugins** window.
2. Find the local Stage Acceptance Plugin.
3. Disable it first if a test is active, then choose **Uninstall/Delete**.
4. Restart Studio and verify that **Startup Studio Tests** is gone.

Use Studio's plugin manager instead of scripting deletion of a user/system plugin folder.

## Automated versus manual evidence

The runner automates contract/state/count/geometry/replication/rebuild checks. The following remain manual:

- artistic quality, readability and overall office composition;
- subjective movement feel and camera experience;
- Script Profiler/MicroProfiler inspection and a long soak for memory trends;
- desktop/mobile/gamepad visual QA beyond the controller/view tests;
- published-experience behavior, DataStore, cross-server persistence and same real-UserId reconnect;
- human review of Output warnings/errors and acceptance artifacts;
- final comparison with `05_MANUAL_QA_GUIDE.md`.

Stage 4 snapshot evidence is still same-server and bounded. It is not Stage 9 persistence.
