# Startup Studio Tycoon

Production-oriented Roblox simulation/tycoon project built with Rojo and strict Luau. Development is performed one accepted roadmap stage at a time.

## Stage 1 toolchain

The project pins its command-line tools in `rokit.toml`:

- Rojo 7.7.0;
- StyLua 2.5.2;
- Selene 0.31.0;
- Wally 0.3.2.

Wally is available through Rokit, but this stage has no package dependency. Therefore, no `wally.toml`, lockfile, or generated package tree is created yet. A manifest must be added together with the first justified dependency.

## Bootstrap

From PowerShell in the repository root:

```powershell
rokit install
stylua --check src tests
selene src tests
pwsh -NoProfile -File scripts/Test-Stage1.ps1
New-Item -ItemType Directory -Path build -Force | Out-Null
rojo build -o build/StartupStudioTycoon.rbxl
rojo serve
```

Open the project in Roblox Studio, connect the installed Rojo 7.7.0 plugin to the local server, and run Play. The Output window should contain both messages:

```text
[StartupStudioTycoon] Server bootstrap ready
[StartupStudioTycoon] Client bootstrap ready
```

Stop `rojo serve` with `Ctrl+C` after the sync check. Roblox Studio MCP may be used for additional inspection, but it is not a Stage 1 blocker.

## Source layout

```text
src/
├─ ReplicatedStorage/
├─ ServerScriptService/
│  └─ Bootstrap/
├─ ServerStorage/
├─ StarterPlayer/
│  └─ StarterPlayerScripts/
│     └─ Bootstrap/
├─ StarterGui/
└─ Workspace/
tests/
├─ unit/
├─ integration/
└─ fixtures/
```

Stage 1 intentionally contains no service registry, remotes, persistent state, economy, employees, office systems, tycoon UI, or monetization.
