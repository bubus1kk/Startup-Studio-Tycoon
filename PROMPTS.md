# Working Prompts for Codex

## Plan

```text
Use $startup-roblox-architect.
Read the roadmap and checklist for Stage <N>.
Do not edit files.
Produce a plan, contracts, tests, risks and Studio checks.
```

## Implement

```text
Use $phase-implementer.
Implement Stage <N> only.
Preserve accepted contracts.
Run checks.
Stop at the gate.
```

## Review

```text
Use $luau-strict-review.
Review uncommitted Luau changes.
Check typing, nil handling, cleanup, boundaries, remote validation and performance.
Fix high-confidence issues.
Run format, lint, tests and build.
```

## Studio

```text
Use $studio-sync-and-verify.
Check Rojo mappings, DataModel paths, remotes, templates and runtime assumptions.
Use Studio MCP if available.
Return exact manual tests.
```

## Economy

```text
Use $economy-save-monetization-audit.
Audit sources, sinks, dead zones, offline income, prestige, save schema and purchase grants.
Return evidence and exact config changes.
```

## Bug

```text
Use $startup-roblox-architect.
Fix the bug with the smallest safe change.
Do not refactor unrelated code.
Add a regression test.
Run checks and provide retest steps.

<BUG REPORT>
```

## Release candidate

```text
Review as a release candidate.
Do not add features.
Prioritize data loss, exploits, purchases, replication, crashes, leaks and onboarding blockers.
Fix only high-confidence issues.
```
