# Startup Studio Tycoon

Production-oriented Roblox simulation/tycoon project built with Rojo and strict Luau. Development is performed one accepted roadmap stage at a time.

## Toolchain

The project pins its command-line tools in `rokit.toml`:

- Rojo 7.7.0;
- StyLua 2.5.2;
- Selene 0.31.0;
- Wally 0.3.2.

Wally is available through Rokit, but this stage has no package dependency. Therefore, no `wally.toml`, lockfile, or generated package tree is created yet. A manifest must be added together with the first justified dependency.

## Build and checks

From PowerShell in the repository root:

```powershell
rokit install
stylua --check src tests
selene src tests
pwsh -NoProfile -File scripts/Test-Stage1.ps1
pwsh -NoProfile -File scripts/Test-Stage2.ps1
New-Item -ItemType Directory -Path build -Force | Out-Null
rojo build -o build/StartupStudioTycoon.rbxl
rojo build test.project.json -o build/StartupStudioTycoonStage2Tests.rbxl
rojo serve
```

GitHub Actions does not run Roblox Studio. The Luau runtime specs in `test.project.json` require a manual Studio Play session with a client; a successful test-project build does not mean those runtime specs passed.

Open the production project in Roblox Studio, connect the installed Rojo 7.7.0 plugin, and run Play. Output should report `server_bootstrap_ready` and `client_bootstrap_ready` without errors. Production `ReplicatedStorage.Remotes` is intentionally empty during Stage 2.

The Stage 2 contracts are documented in [`docs/STAGE_2_ARCHITECTURE.md`](docs/STAGE_2_ARCHITECTURE.md).

Stop `rojo serve` with `Ctrl+C` after the sync check. Roblox Studio MCP may be used for additional inspection, but the required Studio runtime checks still need explicit evidence.

## Source layout

```text
src/
├─ ReplicatedStorage/
│  └─ Shared/
├─ ServerScriptService/
│  ├─ Bootstrap/
│  ├─ Config/
│  └─ Infrastructure/
├─ ServerStorage/
│  └─ Config/
├─ StarterPlayer/
│  └─ StarterPlayerScripts/
│     ├─ Bootstrap/
│     └─ Infrastructure/
├─ StarterGui/
└─ Workspace/
tests/
├─ unit/
├─ integration/
└─ fixtures/
```

Stage 2 contains architecture contracts only. It intentionally contains no gameplay remotes, persistent state, economy, employees, office systems, tycoon UI, or monetization.
