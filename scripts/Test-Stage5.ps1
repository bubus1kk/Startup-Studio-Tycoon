[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$script:assertionCount = 0

function Assert-Stage5 {
	param([bool]$Condition, [string]$Message)
	$script:assertionCount++
	if (-not $Condition) { throw "Stage 5 structural assertion failed: $Message" }
}

function Read-Stage5File {
	param([string]$RelativePath)
	$path = Join-Path $projectRoot $RelativePath
	Assert-Stage5 -Condition (Test-Path -LiteralPath $path -PathType Leaf) -Message "Missing required file: $RelativePath"
	return [System.IO.File]::ReadAllText($path)
}

& (Join-Path $projectRoot "scripts/Test-Stage4.ps1")

$requiredFiles = @(
	"src/ServerStorage/Config/EmployeeDefinitions.lua",
	"src/ServerScriptService/Config/EmployeeConfigValidator.lua",
	"src/ReplicatedStorage/Shared/Types/EmployeeRemoteTypes.lua",
	"src/ServerScriptService/Domain/EmployeeTypes.lua",
	"src/ServerScriptService/Domain/EmployeeProgression.lua",
	"src/ServerScriptService/Domain/CandidateGenerator.lua",
	"src/ServerScriptService/Domain/EmployeeProductivity.lua",
	"src/ServerScriptService/Domain/EmployeeSnapshotSerializer.lua",
	"src/ServerScriptService/Domain/WorkstationDefinitions.lua",
	"src/ServerScriptService/Services/CandidateService.lua",
	"src/ServerScriptService/Services/WorkstationService.lua",
	"src/ServerScriptService/Services/EmployeeService.lua",
	"src/ServerScriptService/Services/EmployeePayrollService.lua",
	"src/ServerScriptService/Services/EmployeeProductivityService.lua",
	"src/ServerScriptService/Services/EmployeeMovementService.lua",
	"src/StarterPlayer/StarterPlayerScripts/Controllers/EmployeesController.lua",
	"src/StarterPlayer/StarterPlayerScripts/UI/EmployeesView.lua",
	"src/StarterPlayer/StarterPlayerScripts/UI/EmployeesTheme.lua",
	"tests/client/EmployeesControllerClientSpec.lua",
	"tests/acceptance/Stage5AcceptanceRouter.server.lua",
	"docs/STAGE_5_ARCHITECTURE.md",
	"docs/STAGE_5_AUTOMATED_ACCEPTANCE.md"
)
foreach ($file in $requiredFiles) { [void](Read-Stage5File $file) }

$employeeConfig = Read-Stage5File "src/ServerStorage/Config/EmployeeDefinitions.lua"
foreach ($role in @("Developer", "Designer", "QAEngineer", "Marketer", "ProductManager", "SystemAdministrator", "HRSpecialist", "Executive", "Researcher")) {
	Assert-Stage5 -Condition ($employeeConfig.Contains('"' + $role + '"')) -Message "Employee role missing: $role"
}
foreach ($grade in @("Trainee", "Junior", "Specialist", "Expert")) {
	Assert-Stage5 -Condition ($employeeConfig.Contains('id = "' + $grade + '"')) -Message "Employee grade missing: $grade"
}
foreach ($trait in @("FastLearner", "Focused", "TeamPlayer", "Efficient", "Perfectionist", "Reliable", "Workaholic", "Creative", "Independent", "Mentor", "Eager", "Methodical")) {
	Assert-Stage5 -Condition ($employeeConfig.Contains('trait("' + $trait + '"')) -Message "Employee trait missing: $trait"
}
foreach ($contract in @("poolSize = 3", "ttlSeconds = 300", "refreshCooldownSeconds = 120", "intervalSeconds = 60", "productivitySeconds = 1", "stuckSeconds = 0.5", "maxEmployeesPerPlayer = 30", "rosterPageSize = 5")) {
	Assert-Stage5 -Condition ($employeeConfig.Contains($contract)) -Message "Employee config contract missing: $contract"
}
foreach ($capacity in @("Developer = { 1, 3, 5 }", "Designer = { 1, 2, 4 }", "QAEngineer = { 1, 2, 4 }", "Marketer = { 1, 2, 4 }", "ProductManager = { 1, 2, 3 }", "SystemAdministrator = { 1, 2, 3 }", "HRSpecialist = { 1, 1, 2 }", "Executive = { 1, 1, 1 }", "Researcher = { 1, 2, 4 }")) {
	Assert-Stage5 -Condition ($employeeConfig.Contains($capacity)) -Message "Workstation capacity missing: $capacity"
}

$validator = Read-Stage5File "src/ServerScriptService/Config/EmployeeConfigValidator.lua"
foreach ($contract in @("DuplicateEmployeeTrait", "EmployeeTierWeightInvalid", "EmployeeWorkstationPrefixInvalid", "EmployeeWorkstationEnvelopeInvalid", "l3Total ~= 30", "EmployeeSchedulerInvalid")) {
	Assert-Stage5 -Condition ($validator.Contains($contract)) -Message "Employee config validation missing: $contract"
}

$remoteDefinitions = Read-Stage5File "src/ReplicatedStorage/Shared/Remotes/RemoteDefinitions.lua"
foreach ($remote in @("RequestOfficeCatalog", "RequestOfficePurchase", "RequestEmployeeOverview", "RequestEmployeeHire", "RequestEmployeeAssignment", "RequestEmployeeDismiss", "RequestCandidateRefresh")) {
	Assert-Stage5 -Condition (([regex]::Matches($remoteDefinitions, 'name\s*=\s*"' + $remote + '"')).Count -eq 1) -Message "Production remote must appear once: $remote"
}
$hireValidatorStart = $remoteDefinitions.IndexOf("local employeeHireRequestValidator")
$assignmentValidatorStart = $remoteDefinitions.IndexOf("local employeeAssignmentRequestValidator")
Assert-Stage5 -Condition ($hireValidatorStart -ge 0 -and $assignmentValidatorStart -gt $hireValidatorStart) -Message "Employee mutation validators are missing"
$hireValidator = $remoteDefinitions.Substring($hireValidatorStart, $assignmentValidatorStart - $hireValidatorStart)
foreach ($forbidden in @("price", "salary", "stats", "grade", "trait", "morale", "CFrame", "ownerUserId")) {
	Assert-Stage5 -Condition (-not $hireValidator.Contains($forbidden)) -Message "Forbidden hire payload field found: $forbidden"
}

$employeeService = Read-Stage5File "src/ServerScriptService/Services/EmployeeService.lua"
foreach ($contract in @("ReserveDebit", "CommitDebit", "RollbackCommittedDebit", "RequestIdConflict", "EmployeeMutationInProgress", "FindFirstFree", "RestoreAssignments", "StopMutations", "GetRoleWorkLedger", "GetTeamProductivityProfile", "MAX_DISMISSED_IDS", "rememberDismissed")) {
	Assert-Stage5 -Condition ($employeeService.Contains($contract)) -Message "Employee aggregate contract missing: $contract"
}
Assert-Stage5 -Condition (-not $employeeService.Contains(")(self._")) -Message "Adjacent employee service calls were parsed as a chained return-value call"
Assert-Stage5 -Condition (-not $employeeService.Contains("runtimeGeneration(self._")) -Message "Runtime generation assignment was parsed as a function call"
Assert-Stage5 -Condition (-not $employeeService.Contains("= now(")) -Message "Scheduler timestamp assignment was parsed as a function call"
$movement = Read-Stage5File "src/ServerScriptService/Services/EmployeeMovementService.lua"
foreach ($contract in @("PathfindingService", "PhysicsService", "CollisionGroupSetCollidable", "minimumPathRequestSeconds", "MinimumPathInterval", "maxPathRequestsPerPlayerPerSecond", "GetMetrics", "stuckAfterSeconds", "recoveryAttempt", "PlotBounds.containsPoint", "Animator", "BaseScript")) {
	Assert-Stage5 -Condition ($movement.Contains($contract)) -Message "Movement/recovery contract missing: $contract"
}
foreach ($animationContract in @("workTrack", "ProceduralFallback", "employee_animation_load_failed", "_stepAnimations", "AnimationFallbackActive")) {
	Assert-Stage5 -Condition ($movement.Contains($animationContract)) -Message "Production animation fallback missing: $animationContract"
}
foreach ($locomotionContract in @("KinematicPivotTo", "AnchoredForKinematicPivotTo", "NormalPathStepCount", "NormalPathDistance", "NormalPathStartWorldPosition", "NormalPathLastWorldPosition", "RecoveryTeleportCount")) {
	Assert-Stage5 -Condition ($movement.Contains($locomotionContract)) -Message "Kinematic locomotion evidence missing: $locomotionContract"
}
Assert-Stage5 -Condition ($movement.Contains("runtime.model:PivotTo") -and -not $movement.Contains("humanoid:MoveTo")) -Message "NPC locomotion mechanism changed from bounded kinematic PivotTo"
foreach ($animationName in @("idle", "walk", "work")) {
	Assert-Stage5 -Condition ($employeeConfig -match ($animationName + '\s*=\s*"rbxassetid://\d+"')) -Message "Central animation ID missing: $animationName"
}
Assert-Stage5 -Condition (-not $movement.Contains("PlayerAdded:Connect")) -Message "Movement service must not own PlayerAdded"
Assert-Stage5 -Condition (-not $employeeService.Contains("PlayerRemoving:Connect")) -Message "Employee service must not own PlayerRemoving"

$playerSession = Read-Stage5File "src/ServerScriptService/Services/PlayerSessionService.lua"
foreach ($contract in @("WorkstationService", "EmployeeService", "EmployeeSessionReady", "snapshot.employee", "employeeService:StopMutations", "employeeService:ExportSession")) {
	Assert-Stage5 -Condition ($playerSession.Contains($contract)) -Message "Player session integration missing: $contract"
}
$officeService = Read-Stage5File "src/ServerScriptService/Services/OfficeBuildingService.lua"
foreach ($contract in @("GetRuntimeContext", "SubscribeRuntimeChanged", "runtimeGeneration", "PurchaseCommitted", "task.defer")) {
	Assert-Stage5 -Condition ($officeService.Contains($contract)) -Message "Office runtime integration missing: $contract"
}

$serverApplication = Read-Stage5File "src/ServerScriptService/Bootstrap/ServerApplication.lua"
$registrationPattern = [regex]::new('(?s)registry:Register\(\{\s*name\s*=\s*"(?<name>[^"]+)"\s*,\s*dependencies\s*=\s*\{(?<dependencies>.*?)\}\s*,\s*value\s*=')
$registrationMatches = $registrationPattern.Matches($serverApplication)
Assert-Stage5 -Condition ($registrationMatches.Count -eq 8) -Message "ServerApplication must register exactly 8 lifecycle objects"
$serviceFiles = [ordered]@{
	ServerRemoteRegistry = "src/ServerScriptService/Infrastructure/ServerRemoteRegistry.lua"
	PlotService = "src/ServerScriptService/Services/PlotService.lua"
	SessionCurrencyService = "src/ServerScriptService/Services/SessionCurrencyService.lua"
	OfficeBuildingService = "src/ServerScriptService/Services/OfficeBuildingService.lua"
	WorkstationService = "src/ServerScriptService/Services/WorkstationService.lua"
	EmployeeMovementService = "src/ServerScriptService/Services/EmployeeMovementService.lua"
	EmployeeService = "src/ServerScriptService/Services/EmployeeService.lua"
	PlayerSessionService = "src/ServerScriptService/Services/PlayerSessionService.lua"
}
$declaredDependencies = @{}
foreach ($registration in $registrationMatches) {
	$name = $registration.Groups["name"].Value
	Assert-Stage5 -Condition (-not $declaredDependencies.ContainsKey($name)) -Message "Duplicate parsed lifecycle registration: $name"
	$dependencies = @($registration.Groups["dependencies"].Value | Select-String -AllMatches '"([^"]+)"' | ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value })
	$declaredDependencies[$name] = $dependencies
}
Assert-Stage5 -Condition ($declaredDependencies.Count -eq $serviceFiles.Count) -Message "Parsed lifecycle registration set is incomplete"
foreach ($name in $serviceFiles.Keys) {
	Assert-Stage5 -Condition ($declaredDependencies.ContainsKey($name)) -Message "Lifecycle registration missing: $name"
	$serviceSource = Read-Stage5File $serviceFiles[$name]
	$requestedDependencies = @([regex]::Matches($serviceSource, 'dependencies:Require\("([^"]+)"\)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
	$declared = @($declaredDependencies[$name] | Sort-Object -Unique)
	Assert-Stage5 -Condition ((($requestedDependencies -join ",") -eq ($declared -join ","))) -Message "Declared/required dependency mismatch for $name"
}
$inDegree = @{}
$dependents = @{}
foreach ($name in $declaredDependencies.Keys) {
	$inDegree[$name] = 0
	$dependents[$name] = @()
}
foreach ($name in $declaredDependencies.Keys) {
	foreach ($dependencyName in $declaredDependencies[$name]) {
		Assert-Stage5 -Condition ($declaredDependencies.ContainsKey($dependencyName)) -Message "Missing lifecycle dependency $dependencyName for $name"
		$inDegree[$name]++
		$dependents[$dependencyName] = @($dependents[$dependencyName]) + $name
	}
}
$readyServices = [System.Collections.Generic.List[string]]::new()
foreach ($readyName in @($inDegree.Keys | Where-Object { $inDegree[$_] -eq 0 } | Sort-Object)) {
	[void]$readyServices.Add($readyName)
}
$startupOrder = [System.Collections.Generic.List[string]]::new()
while ($readyServices.Count -gt 0) {
	$name = $readyServices[0]
	$readyServices.RemoveAt(0)
	[void]$startupOrder.Add($name)
	foreach ($dependentName in @($dependents[$name] | Sort-Object)) {
		$inDegree[$dependentName]--
		if ($inDegree[$dependentName] -eq 0) {
			[void]$readyServices.Add($dependentName)
			$sortedReadyServices = @($readyServices | Sort-Object)
			$readyServices.Clear()
			$readyServices.AddRange([string[]]$sortedReadyServices)
		}
	}
}
Assert-Stage5 -Condition ($startupOrder.Count -eq $declaredDependencies.Count) -Message "ServerApplication lifecycle graph contains a cycle"
Assert-Stage5 -Condition ((@($declaredDependencies.OfficeBuildingService | Sort-Object) -join ",") -eq "PlotService,ServerRemoteRegistry,SessionCurrencyService") -Message "OfficeBuildingService gained employee dependencies"
Assert-Stage5 -Condition ((@($declaredDependencies.WorkstationService) -join ",") -eq "OfficeBuildingService") -Message "WorkstationService must consume the office runtime event"
Assert-Stage5 -Condition ($officeService.Contains("pcall(listener, context)") -and $officeService.Contains("task.defer")) -Message "Office runtime callback failures are not isolated"
$workstationService = Read-Stage5File "src/ServerScriptService/Services/WorkstationService.lua"
Assert-Stage5 -Condition ($workstationService.Contains("SubscribeRuntimeChanged") -and $workstationService.Contains("self._unsubscribeOffice()")) -Message "Workstation office event subscription is not cleaned up"
Write-Host "Stage 5 lifecycle DAG passed: $($startupOrder -join ' -> ')"

$employeesController = Read-Stage5File "src/StarterPlayer/StarterPlayerScripts/Controllers/EmployeesController.lua"
foreach ($contract in @("pcall(self._invokeRemote", "_overviewVersion", "_mutationVersion", "_isCurrentView", "EmployeeSessionReady", "Enum.KeyCode.E", "_dismissConfirmEmployeeId")) {
	Assert-Stage5 -Condition ($employeesController.Contains($contract)) -Message "Employees UI async safety missing: $contract"
}

$testRunner = Read-Stage5File "tests/TestRunner.server.lua"
foreach ($spec in @("EmployeeConfigSpec", "CandidateGeneratorSpec", "CandidateServiceSpec", "EmployeeRemoteDefinitionsSpec", "EmployeeProgressionProductivitySpec", "EmployeeSnapshotSerializerSpec", "EmployeePayrollSpec", "WorkstationDefinitionsSpec", "EmployeeHireIntegrationSpec", "EmployeeSnapshotRejoinSpec", "EmployeeNpcCapacitySpec")) {
	Assert-Stage5 -Condition ($testRunner.Contains($spec)) -Message "Runtime test spec is not executed: $spec"
}
foreach ($testFile in Get-ChildItem -LiteralPath (Join-Path $projectRoot "tests") -Recurse -File -Filter "*Employee*Spec.lua") {
	$content = [System.IO.File]::ReadAllText($testFile.FullName)
	Assert-Stage5 -Condition (-not $content.Contains("TODO")) -Message "Placeholder TODO found in $($testFile.Name)"
	Assert-Stage5 -Condition ($content.Contains("run =") -or $content.Contains("tests():") -or ($content.Contains("function ") -and $content.Contains(".run()"))) -Message "Employee spec contains no executable tests: $($testFile.Name)"
}

function Count-TestCases {
	param([string[]]$RelativePaths)
	$count = 0
	foreach ($relativePath in $RelativePaths) {
		$count += [regex]::Matches((Read-Stage5File $relativePath), '\brun\s*=').Count
	}
	return $count
}
$stage4UnitCases = Count-TestCases @(
	"tests/unit/ClientDependencyResolverSpec.lua", "tests/unit/ConfigAndPayloadSpec.lua",
	"tests/unit/LifecycleRegistrySpec.lua", "tests/unit/PlotBoundsSpec.lua", "tests/unit/PlotConfigSpec.lua",
	"tests/unit/OfficeCatalogSpec.lua", "tests/unit/OfficeConfigSpec.lua", "tests/unit/OfficeGeometryValidatorSpec.lua",
	"tests/unit/OfficeLayoutSerializerSpec.lua", "tests/unit/OfficePlacementSpec.lua", "tests/unit/OfficeProgressionSpec.lua",
	"tests/unit/OfficeSnapshotCacheSpec.lua", "tests/unit/OfficeTemplateContentSpec.lua",
	"tests/unit/RequestRateLimiterSpec.lua", "tests/unit/SessionCurrencyServiceSpec.lua"
)
$stage4IntegrationCases = Count-TestCases @(
	"tests/integration/PlotServiceIntegrationSpec.lua", "tests/integration/ProductionPlotRuntimeSpec.lua",
	"tests/integration/RemoteRegistryIntegrationSpec.lua", "tests/integration/OfficeEntranceApproachSpec.lua",
	"tests/integration/OfficeFullLayoutPerformanceSpec.lua", "tests/integration/OfficeItemPurchaseSpec.lua",
	"tests/integration/OfficeMultiplayerSpec.lua", "tests/integration/OfficeReconstructionSpec.lua",
	"tests/integration/OfficeRejoinSpec.lua", "tests/integration/OfficeRemoteSpec.lua",
	"tests/integration/OfficeRollbackSpec.lua", "tests/integration/OfficeRoomPurchaseSpec.lua",
	"tests/integration/OfficeTierTransitionSpec.lua", "tests/integration/OfficeUpgradeSpec.lua",
	"tests/integration/ProductionOfficeRuntimeSpec.lua"
)
$stage5UnitCases = Count-TestCases @(
	"tests/unit/CandidateGeneratorSpec.lua", "tests/unit/CandidateServiceSpec.lua", "tests/unit/EmployeeConfigSpec.lua",
	"tests/unit/EmployeePayrollSpec.lua", "tests/unit/EmployeeProgressionProductivitySpec.lua",
	"tests/unit/EmployeeRemoteDefinitionsSpec.lua", "tests/unit/EmployeeSnapshotSerializerSpec.lua",
	"tests/unit/WorkstationDefinitionsSpec.lua"
)
$stage5IntegrationCases = Count-TestCases @(
	"tests/integration/EmployeeHireIntegrationSpec.lua", "tests/integration/EmployeeNpcCapacitySpec.lua",
	"tests/integration/EmployeeSnapshotRejoinSpec.lua"
)
$pluginCaseCount = Count-TestCases @("tests/acceptance/AcceptanceRunnerSpec.lua")
$stage4PluginCases = $pluginCaseCount - 1
$stage5PluginCases = 1
$stage4ClientCases = [regex]::Matches((Read-Stage5File "tests/client/BuildMenuControllerClientSpec.lua"), '(?m)^\s*[A-Za-z][A-Za-z0-9_]*Test\(player\)\s*$').Count
$stage5ClientSource = Read-Stage5File "tests/client/EmployeesControllerClientSpec.lua"
$stage5ClientCases = 0
foreach ($clientCase in @("exceptionCleanupAndRetry", "outOfOrderRosterPageCannotRedraw", "destroyInvalidatesPending", "dismissConfirmDoesNotEnterPayload", "closingViewDoesNotCancelMutation", "expiredCountdownDisablesHire")) {
	Assert-Stage5 -Condition ($stage5ClientSource.Contains("`t$clientCase(")) -Message "Stage 5 client scenario missing: $clientCase"
	$stage5ClientCases++
}
Assert-Stage5 -Condition ($stage4UnitCases -eq 33 -and $stage4IntegrationCases -eq 28) -Message "Accepted 61-case Stage 4 functional server baseline changed"
Assert-Stage5 -Condition ($stage4PluginCases -eq 11 -and $stage4ClientCases -eq 4) -Message "Stage 4 plugin/client case count changed"
Assert-Stage5 -Condition ($stage5UnitCases -eq 13 -and $stage5IntegrationCases -eq 12 -and $stage5PluginCases -eq 1) -Message "Stage 5 26-case server addition changed"
Assert-Stage5 -Condition (($stage4UnitCases + $stage4IntegrationCases + $stage4PluginCases) -eq 72) -Message "Stage 4 structured server total must be 72"
Assert-Stage5 -Condition (($stage4UnitCases + $stage4IntegrationCases + $stage4PluginCases + $stage5UnitCases + $stage5IntegrationCases + $stage5PluginCases) -eq 98) -Message "Stage 5 structured server total must be 98"
Assert-Stage5 -Condition ($stage5ClientCases -eq 6) -Message "Stage 5 client scenario count changed"
Write-Host "Runtime case breakdown passed: Stage4=33 unit + 28 integration + 11 plugin = 72 server, 4 client; Stage5=+13 unit + 12 integration + 1 plugin = 98 server, +6 client."

$plugin = Read-Stage5File "tools/StageAcceptancePlugin/StageAcceptancePlugin.server.lua"
$runner = Read-Stage5File "tools/StageAcceptancePlugin/AcceptanceRunner.lua"
foreach ($suite in @("Stage 5 Runtime", "Stage 5 Solo", "Stage 5 Multiplayer 3", "Stage 5 NPC 10", "Stage 5 NPC 30", "Stage 5 Blocked Path", "Stage 5 Full")) {
	Assert-Stage5 -Condition ($plugin.Contains($suite)) -Message "Stage Acceptance Plugin button missing: $suite"
}
foreach ($contract in @("sumSuiteTimeouts(STAGE5_FULL_SEQUENCE)", "STAGE5_FULL_EDIT_MODE_BARRIER_BUDGET_SECONDS", "STAGE5_FULL_SAFETY_MARGIN_SECONDS = 300", "result.total < 98", "Stage5Runtime", "Stage5Solo", "Stage5Multiplayer3", "Stage5Npc10", "Stage5Npc30", "Stage5BlockedPath", "Stage5Full")) {
	Assert-Stage5 -Condition ($runner.Contains($contract)) -Message "Stage 5 acceptance route missing: $contract"
}
Assert-Stage5 -Condition (-not $runner.Contains("STAGE5_FULL_TIMEOUT_SECONDS = 1200")) -Message "Stage 5 Full still uses the unsafe fixed timeout"
$suiteTimeoutSum = 0
foreach ($timeoutMatch in [regex]::Matches($runner, 'timeoutSeconds\s*=\s*(\d+)')) {
	$suiteTimeoutSum += [int]$timeoutMatch.Groups[1].Value
}
$editModeBarrierBudget = 10 * 2 * 30
$fullSafetyMargin = 300
$calculatedFullTimeout = $suiteTimeoutSum + $editModeBarrierBudget + $fullSafetyMargin
Assert-Stage5 -Condition ($suiteTimeoutSum -eq 2130) -Message "Stage 5 Full suite timeout sum changed from 2130 seconds"
Assert-Stage5 -Condition ($calculatedFullTimeout -eq 3030 -and $calculatedFullTimeout -gt ($suiteTimeoutSum + $editModeBarrierBudget)) -Message "Stage 5 Full timeout does not cover suite timeouts plus orchestration overhead"
$acceptanceRunnerSpec = Read-Stage5File "tests/acceptance/AcceptanceRunnerSpec.lua"
foreach ($timeoutRegression in @("fullSuiteTimeoutSeconds, 2130", "fullEditModeBarrierBudgetSeconds, 600", "fullSafetyMarginSeconds, 300", "fullTimeoutSeconds, 3030")) {
	Assert-Stage5 -Condition ($acceptanceRunnerSpec.Contains($timeoutRegression)) -Message "Stage 5 Full timeout unit regression missing: $timeoutRegression"
}
$npcAcceptance = Read-Stage5File "tests/acceptance/Stage5NpcAcceptance.lua"
foreach ($contract in @("PathRequestPeakPerSecond", "MinimumPathInterval", "furniture_recreation", "EmployeeDismissAll", "No NPC changed world position through the ordinary waypoint path", "NormalPathStartWorldPosition", "NormalPathLastWorldPosition")) {
	Assert-Stage5 -Condition ($npcAcceptance.Contains($contract)) -Message "NPC acceptance budget check missing: $contract"
}
$blockedAcceptance = Read-Stage5File "tests/acceptance/Stage5BlockedPathAcceptance.lua"
foreach ($contract in @("RecoveryCount", "PathRequestCount", "MinimumPathInterval")) {
	Assert-Stage5 -Condition ($blockedAcceptance.Contains($contract)) -Message "Blocked-path measured recovery missing: $contract"
}

$productionProject = Read-Stage5File "default.project.json"
$testProjectText = Read-Stage5File "test.project.json"
$testProject = $testProjectText | ConvertFrom-Json
Assert-Stage5 -Condition ($testProject.name -eq "StartupStudioTycoonStage5Tests") -Message "Stage 5 test project name is incorrect"
Assert-Stage5 -Condition ($testProject.tree.ServerScriptService.Stage5Acceptance.Stage5AcceptanceRouter.'$path' -eq "tests/acceptance/Stage5AcceptanceRouter.server.lua") -Message "Stage 5 acceptance router is not mapped"
foreach ($testOnly in @("tests/", "tools/", "Stage4Acceptance", "Stage5Acceptance", "TestSupport")) {
	Assert-Stage5 -Condition (-not $productionProject.Contains($testOnly)) -Message "Test/plugin content leaked into production mapping: $testOnly"
}

$productionText = (Get-ChildItem -LiteralPath (Join-Path $projectRoot "src") -Recurse -File -Filter "*.lua" | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n"
foreach ($forbidden in @("DataStoreService", "ProfileService", "RevenueService", "ProductDevelopmentService", "ReleaseScoreCalculator")) {
	Assert-Stage5 -Condition (-not $productionText.Contains($forbidden)) -Message "Deferred Stage 6/9 system found in Stage 5: $forbidden"
}

$ci = Read-Stage5File ".github/workflows/ci.yml"
foreach ($contract in @("name: Stage 1 through 5 CI", "stylua --check src tests tools", "selene src tests tools", "Test-Stage5.ps1", "StartupStudioTycoonStage5Tests.rbxl", "Build-StageAcceptancePlugin.ps1", "Reject conflict markers")) {
	Assert-Stage5 -Condition ($ci.Contains($contract)) -Message "Stage 5 CI contract missing: $contract"
}

$conflicts = & git -C $projectRoot grep -n -e "^<<<<<<< " -e "^=======$" -e "^>>>>>>> " 2>$null
Assert-Stage5 -Condition ($LASTEXITCODE -eq 1 -and -not $conflicts) -Message "Git conflict markers were found"

$productionSourcemap = [System.IO.Path]::GetTempFileName()
$testSourcemap = [System.IO.Path]::GetTempFileName()
try {
	& rojo sourcemap (Join-Path $projectRoot "default.project.json") --output $productionSourcemap | Out-Host
	if ($LASTEXITCODE -ne 0) { throw "Production sourcemap failed" }
	& rojo sourcemap (Join-Path $projectRoot "test.project.json") --output $testSourcemap | Out-Host
	if ($LASTEXITCODE -ne 0) { throw "Stage 5 test sourcemap failed" }
	$productionMap = [System.IO.File]::ReadAllText($productionSourcemap)
	$testMap = [System.IO.File]::ReadAllText($testSourcemap)
	Assert-Stage5 -Condition ($productionMap.Contains("EmployeeService")) -Message "EmployeeService is absent from production sourcemap"
	Assert-Stage5 -Condition ($productionMap.Contains("EmployeesController")) -Message "EmployeesController is absent from production sourcemap"
	Assert-Stage5 -Condition (-not $productionMap.Contains("Stage5Acceptance")) -Message "Stage 5 acceptance leaked into production sourcemap"
	Assert-Stage5 -Condition ($testMap.Contains("Stage5AcceptanceRouter")) -Message "Stage 5 router is absent from test sourcemap"
}
finally {
	Remove-Item -LiteralPath $productionSourcemap, $testSourcemap -Force -ErrorAction SilentlyContinue
}

Write-Host "Stage 5 structural tests passed ($script:assertionCount Stage 5 assertions plus Stage 4 regression)."
