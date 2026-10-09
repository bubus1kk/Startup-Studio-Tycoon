# Stage 5 — Automated Roblox Studio acceptance

## Artifacts and isolation

Build from repository root on `stage/05-employees`:

```powershell
pwsh -NoProfile -File scripts/Build-StageAcceptancePlugin.ps1
rojo build test.project.json -o build/StartupStudioTycoonStage5Tests.rbxl
rojo build default.project.json -o build/StartupStudioTycoon.rbxl
```

The plugin sources are mapped only by `stage-acceptance-plugin.project.json`. Stage 4/5 acceptance routers, fixtures and client probes are mapped only by `test.project.json`. `default.project.json` contains neither. The build script creates `build/StageAcceptancePlugin.rbxm`; it never installs, publishes or copies a plugin into a user/system directory.

## Plugin suites

All accepted Stage 4 buttons remain. Stage 5 adds:

| Button | Studio call | Timeout |
|---|---|---:|
| Stage 5 Runtime | `ExecutePlayModeAsync("Stage5RuntimeGate")` | 120 s |
| Stage 5 Solo | `ExecutePlayModeAsync(args)` | 180 s |
| Stage 5 Multiplayer 3 | `ExecuteMultiplayerTestAsync(3, args)` | 240 s |
| Stage 5 NPC 10 | `ExecutePlayModeAsync(args)` | 300 s |
| Stage 5 NPC 30 | `ExecutePlayModeAsync(args)` | 480 s |
| Stage 5 Blocked Path | `ExecutePlayModeAsync(args)` | 180 s |
| Stage 5 Full | ten suites below | dynamically calculated: 3030 s with current definitions |

Stage 5 Full runs `Stage 4 Runtime → Stage 4 Solo → Stage 4 Multiplayer 3 → Stage 4 Performance 6 → Stage 5 Runtime → Stage 5 Solo → Stage 5 Multiplayer 3 → Stage 5 NPC 10 → Stage 5 NPC 30 → Stage 5 Blocked Path`.

The Full deadline is calculated from the same suite definitions used for routing: `2130 s` suite timeout sum + `600 s` for twenty mandatory Edit Mode barriers (before/after ten suites at up to 30 seconds) + `300 s` safety margin = `3030 s`. Adding or changing a suite therefore changes the deadline without a second hard-coded total.

Each route owns a watchdog and calls `StudioTestService:EndTest(result)` through `finalizeOnce`. Nil/invalid results are infrastructure FAIL. Before and after every Studio execution, the plugin waits for stable Edit Mode. All toolbar buttons are restored after success, failure, exception or timeout. Full keeps completed reports in the aggregate.

## Install/update Local Plugin

1. Build `build/StageAcceptancePlugin.rbxm`.
2. Open a temporary blank place in Studio.
3. Insert the top-level `StageAcceptancePlugin` model.
4. Select it and choose **Save as Local Plugin**.
5. Remove the inserted model or close the temporary place without saving.
6. When updating, disable/remove the old local plugin, repeat installation and restart Studio.

The script does not perform this user-level installation.

## Required run

1. Open `build/StartupStudioTycoonStage5Tests.rbxl`.
2. Clear Output.
3. Run separately: Stage 5 Runtime, Solo, Multiplayer 3, NPC 10, NPC 30, Blocked Path.
4. Run Stage 5 Full three times consecutively.
5. Save structured counts, failures, metrics, duration and Output with the tested commit SHA/working-tree note.

Runtime counts are collected from executed specs; they are not fabricated by the router. The previously accepted 61 Stage 4 functional server cases are still present (33 unit + 28 integration); `TestRunner` also executes 11 plugin-orchestration cases, so the structured `Stage4Runtime` server total is 72. `Stage5Runtime` adds 26 cases (13 unit + 12 integration + one plugin-orchestration case) for a structured server total of 98. Four Stage 4 client scenarios and six Stage 5 client scenarios run as a client sidecar and are not added to the server `total`. Full validates suite names/count consistency and preserves Stage 4 results. Do not use the production place for automated acceptance.

NPC 10/30 assert unique employee/workstation IDs, one Humanoid/Animator, no scripts/crowd collision, the explicit anchored-root `KinematicPivotTo` contract, non-zero ordinary waypoint steps/world displacement separate from recovery teleports, configured idle/walk/work animation routing, safe asset-or-procedural mode, animation-state restart across a post-hire office rebuild, one central scheduler, the eight-per-second path budget, the two-second per-NPC retry floor, no path growth after settle, preserved NPC identity and zero models/reservations after bounded dismiss cleanup. Blocked Path encloses the target, observes recompute/retry/final reposition counters, checks post-recovery path stability and rejects movement outside the owned plot. Multiplayer 3 waits for one real payroll cycle, checks per-player exact salary debit and role-ledger growth, then removes one client and verifies survivor isolation.

## Production smoke

Open `build/StartupStudioTycoon.rbxl` and verify normal player spawn, Stage 4 Build menu, Employees menu, one Developer hire, NPC travel, increasing work points/XP, Reset Character without duplicate UI/NPC, clean Output and no Stage4/Stage5 test content.

## Manual evidence still required

Studio acceptance cannot be inferred from CLI build. Human review remains required for movement feel, visual clipping, multiplayer replication, blocked navigation, Script Profiler/MicroProfiler, 30-minute soak, desktop/mobile/gamepad usability and Output warnings. Stage 5 snapshots are same-server only; no DataStore/cross-server claim is made.
