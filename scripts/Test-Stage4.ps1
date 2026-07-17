[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$script:assertionCount = 0

function Assert-Stage4 {
	param(
		[Parameter(Mandatory = $true)][bool]$Condition,
		[Parameter(Mandatory = $true)][string]$Message
	)
	$script:assertionCount += 1
	if (-not $Condition) {
		throw "Stage 4 assertion failed: $Message"
	}
}

function Read-ProjectFile {
	param([Parameter(Mandatory = $true)][string]$RelativePath)
	return Get-Content -Raw -LiteralPath (Join-Path $projectRoot $RelativePath)
}

function Find-SourcemapChild {
	param([Parameter(Mandatory = $true)][object]$Node, [Parameter(Mandatory = $true)][string]$Name)
	return $Node.children | Where-Object { $_.name -eq $Name } | Select-Object -First 1
}

function Assert-SourcemapPath {
	param(
		[Parameter(Mandatory = $true)][object]$Root,
		[Parameter(Mandatory = $true)][string[]]$Segments,
		[Parameter(Mandatory = $true)][string]$Description
	)
	$current = $Root
	foreach ($segment in $Segments) {
		$current = Find-SourcemapChild -Node $current -Name $segment
		Assert-Stage4 -Condition ($null -ne $current) -Message "$Description is missing segment $segment"
	}
	return $current
}

$productionFiles = @(
	"src/ReplicatedStorage/Shared/Types/OfficeRemoteTypes.lua",
	"src/ServerScriptService/Config/OfficeConfigValidator.lua",
	"src/ServerScriptService/Config/SessionCurrencyConfigValidator.lua",
	"src/ServerScriptService/Domain/OfficeTypes.lua",
	"src/ServerScriptService/Domain/OfficeCatalog.lua",
	"src/ServerScriptService/Domain/OfficeProgression.lua",
	"src/ServerScriptService/Domain/OfficePlacement.lua",
	"src/ServerScriptService/Domain/OfficeGeometryValidator.lua",
	"src/ServerScriptService/Domain/OfficeLayoutSerializer.lua",
	"src/ServerScriptService/Security/RequestRateLimiter.lua",
	"src/ServerScriptService/Services/SessionCurrencyService.lua",
	"src/ServerScriptService/Services/OfficeSnapshotCache.lua",
	"src/ServerScriptService/Services/OfficeBuildingService.lua",
	"src/ServerScriptService/Systems/OfficeLayoutBuilder.lua",
	"src/ServerScriptService/Systems/PlotRuntimeBuilder.lua",
	"src/ServerStorage/Config/OfficeDefinitions.lua",
	"src/ServerStorage/Config/SessionCurrencyConfig.lua",
	"src/StarterPlayer/StarterPlayerScripts/Controllers/BuildMenuController.lua",
	"src/StarterPlayer/StarterPlayerScripts/UI/BuildMenuView.lua",
	"src/StarterPlayer/StarterPlayerScripts/UI/BuildMenuTheme.lua"
)

$unitSpecs = @(
	"OfficeConfigSpec", "OfficeCatalogSpec", "OfficeProgressionSpec", "OfficePlacementSpec",
	"OfficeLayoutSerializerSpec", "SessionCurrencyServiceSpec", "OfficeSnapshotCacheSpec",
	"RequestRateLimiterSpec", "OfficeGeometryValidatorSpec"
)
$runtimeSpecs = @(
	"OfficeRoomPurchaseSpec", "OfficeEntranceApproachSpec", "OfficeItemPurchaseSpec", "OfficeUpgradeSpec", "OfficeTierTransitionSpec",
	"OfficeRollbackSpec", "OfficeReconstructionSpec", "OfficeRejoinSpec", "OfficeRemoteSpec",
	"OfficeMultiplayerSpec", "OfficeFullLayoutPerformanceSpec", "ProductionOfficeRuntimeSpec"
)
$requiredTestSupport = @(
	"tests/serverFixtures/OfficeTestUtils.lua",
	"tests/fixtures/InvalidOfficeDefinitions.lua",
	"tests/serverFixtures/FailureOfficeTemplates.lua",
	"tests/OfficeSecurityProbe.server.lua",
	"tests/OfficeSecurityProbe.client.lua"
)

foreach ($relativePath in $productionFiles) {
	Assert-Stage4 -Condition (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath) -PathType Leaf) -Message "Production Stage 4 file is missing: $relativePath"
	Assert-Stage4 -Condition ((Read-ProjectFile $relativePath).StartsWith("--!strict")) -Message "Strict mode is missing: $relativePath"
}
foreach ($spec in $unitSpecs) {
	$relativePath = "tests/unit/$spec.lua"
	Assert-Stage4 -Condition (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath) -PathType Leaf) -Message "Unit spec missing: $spec"
}
foreach ($spec in $runtimeSpecs) {
	$relativePath = "tests/integration/$spec.lua"
	Assert-Stage4 -Condition (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath) -PathType Leaf) -Message "Runtime spec missing: $spec"
}
foreach ($relativePath in $requiredTestSupport) {
	Assert-Stage4 -Condition (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath) -PathType Leaf) -Message "Stage 4 fixture/probe missing: $relativePath"
}

$officeConfig = Read-ProjectFile "src/ServerStorage/Config/OfficeDefinitions.lua"
foreach ($tier in @("Garage", "Small Loft", "Downtown Office", "Tech Campus", "Global HQ")) {
	Assert-Stage4 -Condition ($officeConfig.Contains("`"$tier`"")) -Message "Tier config missing: $tier"
}
foreach ($room in @("Development Room", "Design Studio", "QA Lab", "Marketing Room", "Meeting Room", "Server Room", "Recreation Area", "Executive Office", "Research Lab")) {
	Assert-Stage4 -Condition ($officeConfig.Contains("`"$room`"")) -Message "Room config missing: $room"
}
Assert-Stage4 -Condition ($officeConfig.Contains("local itemContent =")) -Message "Equipment/furniture catalog is missing"
Assert-Stage4 -Condition ($officeConfig.Contains("local upgrades = {}")) -Message "Upgrade chains are missing"
$officeConfigSpec = Read-ProjectFile "tests/unit/OfficeConfigSpec.lua"
foreach ($contract in @("#config.tiers, 5", "#config.rooms, 9", "#config.items, 18", "#config.upgrades, 9", "total, 205150")) {
	Assert-Stage4 -Condition ($officeConfigSpec.Contains($contract)) -Message "Config count/price regression is missing: $contract"
}

$templateRoot = Join-Path $projectRoot "src/ServerStorage/OfficeTemplates"
$tierTemplates = @(Get-ChildItem -LiteralPath (Join-Path $templateRoot "Tiers") -File -Filter "*.model.json")
$roomTemplates = @(Get-ChildItem -LiteralPath (Join-Path $templateRoot "Rooms") -File -Filter "*.model.json")
$equipmentTemplates = @(Get-ChildItem -LiteralPath (Join-Path $templateRoot "Equipment") -File -Filter "*.model.json")
$furnitureTemplates = @(Get-ChildItem -LiteralPath (Join-Path $templateRoot "Furniture") -File -Filter "*.model.json")
Assert-Stage4 -Condition ($tierTemplates.Count -eq 5) -Message "Expected 5 tier templates, got $($tierTemplates.Count)"
Assert-Stage4 -Condition ($roomTemplates.Count -eq 9) -Message "Expected 9 room templates, got $($roomTemplates.Count)"
Assert-Stage4 -Condition ($equipmentTemplates.Count -eq 27) -Message "Expected 27 equipment templates, got $($equipmentTemplates.Count)"
Assert-Stage4 -Condition ($furnitureTemplates.Count -eq 9) -Message "Expected 9 furniture templates, got $($furnitureTemplates.Count)"
$templates = @($tierTemplates + $roomTemplates + $equipmentTemplates + $furnitureTemplates)
Assert-Stage4 -Condition ($templates.Count -eq 50) -Message "Expected 50 production templates"
$expectedTemplates = @(
	"Garage", "SmallLoft", "DowntownOffice", "TechCampus", "GlobalHQ",
	"DevelopmentRoom", "DesignStudio", "QALab", "MarketingRoom", "MeetingRoom", "ServerRoom", "RecreationArea", "ExecutiveOffice", "ResearchLab",
	"DevelopmentWorkstationL1", "DevelopmentWorkstationL2", "DevelopmentWorkstationL3",
	"DesignWorkstationL1", "DesignWorkstationL2", "DesignWorkstationL3",
	"QATestRigL1", "QATestRigL2", "QATestRigL3",
	"MarketingConsoleL1", "MarketingConsoleL2", "MarketingConsoleL3",
	"MeetingSystemL1", "MeetingSystemL2", "MeetingSystemL3",
	"ServerRackL1", "ServerRackL2", "ServerRackL3",
	"RecreationGamingPodL1", "RecreationGamingPodL2", "RecreationGamingPodL3",
	"ExecutiveDeskL1", "ExecutiveDeskL2", "ExecutiveDeskL3",
	"ResearchComputeBenchL1", "ResearchComputeBenchL2", "ResearchComputeBenchL3",
	"DevelopmentWhiteboard", "DesignMoodboard", "QABugBoard", "MarketingCampaignDisplay", "MeetingCredenza", "ServerCoolingUnit", "RecreationLoungeSet", "ExecutiveAwardCabinet", "ResearchPrototypeCabinet"
)
$actualTemplateNames = @($templates | ForEach-Object { $_.BaseName -replace '\.model$', '' })
foreach ($templateName in $expectedTemplates) {
	Assert-Stage4 -Condition ($actualTemplateNames -contains $templateName) -Message "Expected production template missing: $templateName"
}
$hashes = @{}
$geometrySignatures = @{}
foreach ($template in $templates) {
	$model = Get-Content -Raw -LiteralPath $template.FullName | ConvertFrom-Json
	Assert-Stage4 -Condition ($model.className -eq "Model") -Message "Template root must be Model: $($template.Name)"
	Assert-Stage4 -Condition ($model.children.Count -ge 2) -Message "Pivot-only template is forbidden: $($template.Name)"
	Assert-Stage4 -Condition ($model.children[0].name -eq "Pivot") -Message "Template Pivot missing: $($template.Name)"
	Assert-Stage4 -Condition (-not (($model.children | ForEach-Object { $_.name }) -match 'Signature|Placeholder|TemplateDetail')) -Message "Placeholder template detail found: $($template.Name)"
	$hash = (Get-FileHash -LiteralPath $template.FullName -Algorithm SHA256).Hash
	$hashes[$hash] = $true
	$geometrySignature = @( $model.children | Select-Object -Skip 1 | ForEach-Object {
		[pscustomobject]@{ className = $_.className; properties = $_.properties }
	} ) | ConvertTo-Json -Compress -Depth 8
	$geometrySignatures[$geometrySignature] = $true
}
Assert-Stage4 -Condition ($hashes.Count -eq 50) -Message "Production templates must be distinct"
Assert-Stage4 -Condition ($geometrySignatures.Count -eq 50) -Message "Production template geometry must be distinct independently of names"
$layoutBuilder = Read-ProjectFile "src/ServerScriptService/Systems/OfficeLayoutBuilder.lua"
Assert-Stage4 -Condition ($layoutBuilder.Contains("clone.PrimaryPart = pivot")) -Message "Runtime template clones must assign their Pivot as PrimaryPart"
Assert-Stage4 -Condition ($layoutBuilder.Contains("base * CFrame.new")) -Message "Tier geometry must preserve plot-origin rotation"
Assert-Stage4 -Condition (-not $layoutBuilder.Contains("CFrame.new(center.Position")) -Message "Tier geometry must not reconstruct world-space centers"
Assert-Stage4 -Condition ($layoutBuilder.Contains('"EntranceApproach"')) -Message "Tier geometry must include EntranceApproach"
Assert-Stage4 -Condition ($layoutBuilder.Contains("spawnOfficeEdgeZ")) -Message "EntranceApproach must derive its endpoint from the stable plot spawn"
$entranceApproachSpec = Read-ProjectFile "tests/integration/OfficeEntranceApproachSpec.lua"
foreach ($contract in @("all five tiers", "PlotBounds.containsBox", "previousApproach.Parent == nil", "INSTANCE_BUDGET", "BASE_PART_BUDGET")) {
	Assert-Stage4 -Condition ($entranceApproachSpec.Contains($contract)) -Message "Entrance approach regression is missing: $contract"
}

$remoteDefinitions = Read-ProjectFile "src/ReplicatedStorage/Shared/Remotes/RemoteDefinitions.lua"
foreach ($remoteName in @("RequestOfficeCatalog", "RequestOfficePurchase")) {
	Assert-Stage4 -Condition (([regex]::Matches($remoteDefinitions, "name\s*=\s*`"$remoteName`"")).Count -eq 1) -Message "Approved production remote must appear once: $remoteName"
}
$productionRemoteNames = @([regex]::Matches($remoteDefinitions, 'name\s*=\s*"([A-Za-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value })
Assert-Stage4 -Condition ($productionRemoteNames.Count -eq 2) -Message "Production must contain exactly two approved remotes"
foreach ($testRemote in @("TestPlotMutation", "TestOfficePurchase", "Stage3TestRemotes", "Stage4TestRemotes")) {
	Assert-Stage4 -Condition (-not $remoteDefinitions.Contains($testRemote)) -Message "Test-only remote leaked into production: $testRemote"
}
$purchaseValidatorStart = $remoteDefinitions.IndexOf("local purchaseRequestValidator")
$purchaseValidatorEnd = $remoteDefinitions.IndexOf("local purchaseResponseValidator")
Assert-Stage4 -Condition ($purchaseValidatorStart -ge 0 -and $purchaseValidatorEnd -gt $purchaseValidatorStart) -Message "Purchase validator contract missing"
$purchaseValidator = $remoteDefinitions.Substring($purchaseValidatorStart, $purchaseValidatorEnd - $purchaseValidatorStart)
foreach ($forbidden in @("price", "balance", "plotId", "ownerUserId", "tier", "slot", "anchor", "CFrame", "level", "success")) {
	Assert-Stage4 -Condition (-not $purchaseValidator.Contains($forbidden)) -Message "Forbidden purchase payload field found: $forbidden"
}

$serverApplication = Read-ProjectFile "src/ServerScriptService/Bootstrap/ServerApplication.lua"
foreach ($service in @("SessionCurrencyService", "OfficeBuildingService", "PlayerSessionService")) {
	Assert-Stage4 -Condition ($serverApplication.Contains("name = `"$service`"")) -Message "Lifecycle registration missing: $service"
}
$playerSession = Read-ProjectFile "src/ServerScriptService/Services/PlayerSessionService.lua"
foreach ($serviceFile in @("SessionCurrencyService.lua", "OfficeSnapshotCache.lua", "OfficeBuildingService.lua")) {
	$content = Read-ProjectFile "src/ServerScriptService/Services/$serviceFile"
	Assert-Stage4 -Condition (-not $content.Contains("PlayerAdded:Connect")) -Message "$serviceFile must not own PlayerAdded"
	Assert-Stage4 -Condition (-not $content.Contains("PlayerRemoving:Connect")) -Message "$serviceFile must not own PlayerRemoving"
}
Assert-Stage4 -Condition ($playerSession.Contains("self._players.PlayerAdded:Connect")) -Message "PlayerSessionService must own PlayerAdded"

$stage4ProductionText = ($productionFiles | ForEach-Object { Read-ProjectFile $_ }) -join "`n"
foreach ($forbidden in @("DataStoreService", "ProfileService", "PathfindingService", "HumanoidDescription", "payroll", "prestige")) {
	Assert-Stage4 -Condition (-not $stage4ProductionText.Contains($forbidden)) -Message "Out-of-scope system found in Stage 4 production: $forbidden"
}

foreach ($doc in @("AGENTS.md", "04_STAGE_CHECKLIST.md", "05_MANUAL_QA_GUIDE.md", "docs/STAGE_4_ARCHITECTURE.md")) {
	Assert-Stage4 -Condition (Test-Path -LiteralPath (Join-Path $projectRoot $doc) -PathType Leaf) -Message "Required Stage 4 documentation missing: $doc"
}
$manualQa = Read-ProjectFile "05_MANUAL_QA_GUIDE.md"
Assert-Stage4 -Condition ($manualQa.Contains("Игрок проходит от SpawnLocation до входа без прыжка")) -Message "Manual QA must require a jump-free entrance walk"
$agents = Read-ProjectFile "AGENTS.md"
Assert-Stage4 -Condition ($agents.Contains("scripts/Test-Stage4.ps1")) -Message "AGENTS required checks do not include Stage 4"
$ci = Read-ProjectFile ".github/workflows/ci.yml"
Assert-Stage4 -Condition ($ci.Contains("name: Stage 1 through 4 CI")) -Message "CI display name is not Stage 1 through 4"
Assert-Stage4 -Condition ($ci.Contains("Test-Stage4.ps1")) -Message "CI does not run Stage 4 structural tests"
Assert-Stage4 -Condition ($ci.Contains("StartupStudioTycoonStage4Tests.rbxl")) -Message "CI does not build the Stage 4 test place"

$productionProjectText = Read-ProjectFile "default.project.json"
$testProjectText = Read-ProjectFile "test.project.json"
$testProject = $testProjectText | ConvertFrom-Json
Assert-Stage4 -Condition (-not $productionProjectText.Contains("tests/")) -Message "Production project maps test content"
Assert-Stage4 -Condition ($testProject.name -eq "StartupStudioTycoonStage4Tests") -Message "Stage 4 test project name is incorrect"
Assert-Stage4 -Condition ($testProject.tree.ServerStorage.OfficeTemplates.'$path' -eq "src/ServerStorage/OfficeTemplates") -Message "Test project does not map server-only office templates"
Assert-Stage4 -Condition (-not $productionProjectText.Contains("OfficeSecurityProbe")) -Message "Security probe leaked into production project"
foreach ($testOnlyName in @("TestSupport", "Stage2Tests", "ForeignOwnershipProbe", "OfficeSecurityProbe")) {
	Assert-Stage4 -Condition (-not $productionProjectText.Contains($testOnlyName)) -Message "Test-only mapping leaked into production project: $testOnlyName"
}

$productionSourcemapPath = [System.IO.Path]::GetTempFileName()
$testSourcemapPath = [System.IO.Path]::GetTempFileName()
try {
	& rojo sourcemap (Join-Path $projectRoot "default.project.json") --output $productionSourcemapPath | Out-Host
	if ($LASTEXITCODE -ne 0) { throw "Production sourcemap failed with exit code $LASTEXITCODE" }
	& rojo sourcemap (Join-Path $projectRoot "test.project.json") --output $testSourcemapPath | Out-Host
	if ($LASTEXITCODE -ne 0) { throw "Test sourcemap failed with exit code $LASTEXITCODE" }
	$productionMap = Get-Content -Raw -LiteralPath $productionSourcemapPath | ConvertFrom-Json
	$testMap = Get-Content -Raw -LiteralPath $testSourcemapPath | ConvertFrom-Json
	$null = Assert-SourcemapPath -Root $productionMap -Segments @("ServerScriptService", "Services", "OfficeBuildingService") -Description "Production OfficeBuildingService"
	$null = Assert-SourcemapPath -Root $productionMap -Segments @("ServerStorage", "Config", "OfficeDefinitions") -Description "Production office configuration"
	$null = Assert-SourcemapPath -Root $testMap -Segments @("ServerScriptService", "Stage2Tests", "OfficeSecurityProbe") -Description "Test-only office security server probe"
	Assert-Stage4 -Condition (-not (Get-Content -Raw -LiteralPath $productionSourcemapPath).Contains("OfficeSecurityProbe")) -Message "Test-only office probe leaked into production sourcemap"
}
finally {
	Remove-Item -LiteralPath $productionSourcemapPath -Force -ErrorAction SilentlyContinue
	Remove-Item -LiteralPath $testSourcemapPath -Force -ErrorAction SilentlyContinue
}

Write-Host "Stage 4 structural tests passed ($script:assertionCount assertions)."
