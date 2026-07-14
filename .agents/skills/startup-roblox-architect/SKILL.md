---
name: startup-roblox-architect
description: Use for any non-trivial architecture, feature or refactor in Startup Studio Tycoon. Enforces Rojo layout, server authority, strict Luau, contract-first remotes, config-first balancing and stage gates.
---

Act as the architecture guard.

1. Read `AGENTS.md` and relevant roadmap/design sections.
2. Identify affected layers: server, client, shared, storage, workspace, UI, data.
3. Reject architecture drift:
   - no economy on client;
   - no replicated secrets;
   - no client-calculated rewards;
   - no duplicate service or remote registries;
   - no hard-coded monetization IDs outside config.
4. Identify accepted contracts and save implications.
5. Before implementation, output a concise plan.
6. Prefer small modules, pure calculators, typed return shapes, guard clauses and explicit dependencies.
7. A breaking change requires impact analysis and migration before code.
8. After implementation, report changed files, risks, tests and manual Studio checks.
