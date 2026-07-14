---
name: studio-sync-and-verify
description: Verifies Rojo mapping, Roblox DataModel paths, remotes, templates and Studio runtime assumptions after a change.
---

1. Inspect `default.project.json`.
2. Check every changed `WaitForChild`, service path and template path against Rojo mapping.
3. Check `.server.lua`, `.client.lua` and module placement.
4. Verify remote names and registry contracts.
5. If Studio MCP is available:
   - inspect DataModel;
   - verify expected instances;
   - inspect Output;
   - run a safe smoke test when possible.
6. Do not make visual product decisions.
7. Fix only clear path/sync defects.
8. Return mapping status, missing instances, runtime risks and exact human Studio tests.
