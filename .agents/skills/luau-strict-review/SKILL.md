---
name: luau-strict-review
description: Performs a strict Luau code review for typing, nil safety, cleanup, module boundaries, Roblox runtime risks and maintainability.
---

Review changed Luau files for:

- `--!strict`;
- exported types;
- accidental `any`;
- nil handling;
- unsafe casts;
- hidden side effects;
- connection/task cleanup;
- unbounded loops;
- yield inside critical transactions;
- repeated tree scans;
- duplicated constants;
- client/server violations;
- remote validation;
- misleading names;
- oversized modules;
- missing tests.

Run StyLua, Selene, tests and Rojo build where available. Fix only high-confidence in-scope defects. Report commands that could not run.
