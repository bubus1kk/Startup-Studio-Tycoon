# Stage 5 — Server-authoritative employees and NPC simulation

## Scope

Stage 5 implements employees only: nine roles, four grades, three stats, twelve config-driven traits, a three-slot Candidate Board, hiring, compatible workstation reservation, payroll, morale, XP/levels, role work points, server NPC movement, stuck recovery, a minimal Employees UI and bounded same-server restoration. Products, product assignment, revenue, offline productivity, fatigue, DataStore/ProfileService and monetization remain deferred.

## Ownership and dependency graph

```text
OfficeBuildingService (owns OfficeBuildRoot)
  └─ read-only runtime context/event
     └─ WorkstationService (owns attachments + reservations)
        └─ EmployeeService (owns roster + mutations)
           ├─ CandidateService (owns per-player candidate boards)
           ├─ SessionCurrencyService (owns Cash reservations)
           ├─ EmployeeMovementService (owns visual NPC runtime only)
           ├─ EmployeePayrollService (atomic payroll transition logic)
           └─ EmployeeProductivityService (ledger/XP/morale scheduler logic)

PlayerSessionService is the only PlayerAdded/PlayerRemoving owner.
```

`EmployeeMovementService` never authorizes productivity or mutates Cash. `WorkstationService` never owns or replaces `OfficeBuildRoot`. Candidate, payroll and employee services do not own player lifecycle connections.

## Config and immutable contracts

`ServerStorage.Config.EmployeeDefinitions` is server-only. Startup validates it against the accepted Stage 4 room/equipment/upgrade IDs and then recursively copies/freezes it through `ConfigLoader`.

- roles: Developer, Designer, QAEngineer, Marketer, ProductManager, SystemAdministrator, HRSpecialist, Executive, Researcher;
- grades: Trainee, Junior, Specialist, Expert;
- stats: speed, quality, reliability;
- traits: FastLearner, Focused, TeamPlayer, Efficient, Perfectionist, Reliable, Workaholic, Creative, Independent, Mentor, Eager, Methodical;
- Candidate Board: 3 slots, 300-second server TTL, free 120-second manual refresh;
- payroll: 60 seconds of active server time;
- productivity scheduler: 1 second; centralized stuck detector: 0.5 seconds;
- roster page: 5; maximum employees/NPCs per player: 30.

Validator checks duplicate/unknown IDs, the exact approved role biases, grade ordering/ranges, integer positive currency, the exact twelve trait effects, the exact per-tier grade weights, slot prefixes, local offsets inside the Stage 4 equipment envelope, L3 total 30, schedulers/timeouts and performance budgets. NaN/inf, cyclic/metatable-bearing config and contract-shaped-but-drifted values are rejected before recursive freeze.

## Workstation contract

Logical IDs are `workstation:{roleId}:{slotIndex}`. Existing indices survive L1→L2→L3 replacement.

| Role | L1 | L2 | L3 |
|---|---:|---:|---:|
| Developer | 1 | 3 | 5 |
| Designer | 1 | 2 | 4 |
| QAEngineer | 1 | 2 | 4 |
| Marketer | 1 | 2 | 4 |
| ProductManager | 1 | 2 | 3 |
| SystemAdministrator | 1 | 2 | 3 |
| HRSpecialist | 1 | 1 | 2 |
| Executive | 1 | 1 | 1 |
| Researcher | 1 | 2 | 4 |

L3 totals 30. `WorkstationService` composes config offsets in equipment-pivot local space and creates one approach plus one work `Attachment` per available slot. Authoritative bidirectional maps enforce one employee per workstation and one workstation per employee. A failed reassignment preserves the previous reservation. Office runtime generations discard stale replacement callbacks. Direct equipment/anchor deletion releases affected reservations; an ordinary office upgrade/rebuild preserves valid logical IDs.

## Candidate and mutation transactions

Generation uses injected monotonic clock, random source and name source. Tier grade weights, free compatible roles and authoritative Cash are read on the server. When a compatible free slot and Trainee funding exist, the board is repaired to contain at least one hireable candidate. Expired candidates are replaced by the shared bounded scheduler/overview path; a successful hire replaces the consumed slot immediately.

Employee mutations have a per-player guard and a 64-entry recent response cache. The same request ID/signature is idempotent; a changed signature is `RequestIdConflict`.

Hire order is:

```text
authoritative candidate/expiry/cap/slot validation
→ Cash reserve
→ employee record
→ workstation reservation
→ server NPC creation attempt
→ Cash commit
→ candidate consume/replacement
```

Reservation, roster, sequence, NPC and Cash are rolled back on economic/aggregate failure. A visual NPC failure is logged and does not corrupt the confirmed employee/economy record.

## Payroll, productivity, XP and morale

One centralized employee heartbeat advances bounded deadlines; there is no permanent loop per employee. Payroll builds a stable roster and performs one total Cash reservation. No partial payroll or negative balance is possible. First miss produces `Unpaid`, morale −15 and output ×0.5; later misses produce `Inactive`, morale −10 and zero output; a successful recovery returns `Active` and morale +10. No automatic dismissal occurs.

Productivity uses the authoritative formula and only valid assignments. Active/Unpaid employees generate role-specific work points; inactive, dismissed and unassigned employees generate zero. Movement state is irrelevant. Work points generate XP, deterministic stat growth and grade-capped levels. Morale has no passive decay; bounded Recreation Lounge and active-HR recovery apply positive trait modifiers. The read-only `GetRoleWorkLedger` and `GetTeamProductivityProfile` APIs prepare Stage 6 integration without consuming points or creating revenue.

## NPC runtime and safety

NPCs are server-created, data-light R15-compatible rigs with the standard 16 body parts and Motor6D chain, one Humanoid and one Animator, no scripts/accessories/layered clothing and no per-NPC permanent heartbeat. Locomotion is explicitly kinematic: the server validates a path and applies `Model:PivotTo()` to its waypoints; it does not use `Humanoid:MoveTo` or physics locomotion. `HumanoidRootPart` therefore remains anchored in every movement state, including walking, stuck recovery and rebuild/reassign, while the remaining Motor6D body stays unanchored for animation. A physical `Humanoid:MoveTo` implementation would require an unanchored root and a different floor/collision contract. Parts use the `EmployeeNpcs` collision group and cannot crowd-block employees or players; navigation remains floor-aware through the server path. Idle, walk and workstation-work animation IDs are centralized and loaded through protected asset calls. Load/play failure is logged once per NPC/state and switches that state to a centralized procedural pose fallback, leaving employee simulation intact; movement-state transitions restart the appropriate animation after workstation rebind or office rebuild. Normal waypoint displacement and recovery teleports have separate bounded diagnostics so acceptance can prove ordinary locomotion changed world position. Pathfinding is requested on target changes or recovery, not on productivity/frame ticks. Per-player request budgets and a two-second per-NPC path-request throttle apply; bounded diagnostic counters support acceptance without becoming authority.

Stuck means less than one stud progress for four seconds while a target is active. Recovery is bounded: recompute, validated approach retry, then authoritative reposition. Every target/reposition is checked against the owned plot with `PlotBounds`; callbacks verify employee/model/path/runtime/target identity. Dismiss, session close and service destroy remove all NPC models.

## Production remotes

The centralized registry contains the two accepted Stage 4 functions plus:

- `RequestEmployeeOverview` — `{rosterPage}`;
- `RequestEmployeeHire` — `{requestId, candidateId}`;
- `RequestEmployeeAssignment` — `{requestId, employeeId, workstationId}`;
- `RequestEmployeeDismiss` — `{requestId, employeeId}`;
- `RequestCandidateRefresh` — `{requestId}`.

Validators require exact bounded shapes. Clients cannot submit Cash, price, salary, stats, grade, trait, morale, role, owner, timestamps, productivity, XP, level, plot or CFrame. Responses are bounded to three candidates, five roster records and nine role summaries.

## Session and same-server snapshot

Join order is `Plot → Currency → Office → Workstations → Employees → ready attributes`. Leave order stops employee mutations/schedulers, exports employee/office/currency data into one bounded optional same-server snapshot, closes employees/workstations/office/currency, then releases the plot.

Employee snapshot schema version 1 stores employee data, valid assignments, role ledger, candidate records as remaining TTL, refresh/payroll remaining time and next sequence. It never stores Player, Instance, NPC, Humanoid, connection, path, movement state or absolute client timestamp. Unknown runtime workstation IDs restore as unassigned. Invalid employee snapshot falls back to a fresh employee session without discarding valid office/currency data. This is not cross-server persistence.

## Verification boundary

Runtime specs cover exact config drift rejection, all traits/morale bands/team caps, deterministic candidates, formulas, XP caps, payroll transitions, workstation prefixes, snapshot validation, atomic hire/rollback/idempotency, incompatible assignment, rebuild/upgrade retention, deleted desk, rejoin/progression and 30 NPC rebuild/cleanup capacity. Stage 5 Studio suites cover live production remotes/UI/replication, isolated payroll/ledger/leave, measured blocked-path recovery and 10/30 NPC path/rebuild/cleanup budgets. Rojo/CLI success alone is not Studio PASS.
