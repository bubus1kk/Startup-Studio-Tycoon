[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$script:assertionCount = 0

function Assert-Stage3 {
	param(
		[Parameter(Mandatory = $true)]
		[bool]$Condition,

		[Parameter(Mandatory = $true)]
		[string]$Message
	)

	$script:assertionCount += 1
	if (-not $Condition) {
		throw "Stage 3 assertion failed: $Message"
	}
}

function Read-ProjectFile {
	param(
		[Parameter(Mandatory = $true)]
		[string]$RelativePath
	)

	return Get-Content -Raw -LiteralPath (Join-Path $projectRoot $RelativePath)
}

function Find-SourcemapChild {
	param(
		[Parameter(Mandatory = $true)]
		[object]$Node,

		[Parameter(Mandatory = $true)]
		[string]$Name
	)

	return $Node.children | Where-Object { $_.name -eq $Name } | Select-Object -First 1
}

function Assert-SourcemapPath {
	param(
		[Parameter(Mandatory = $true)]
		[object]$Root,

		[Parameter(Mandatory = $true)]
		[string[]]$Segments,

		[Parameter(Mandatory = $true)]
		[string]$Description
	)

	$current = $Root
	foreach ($segment in $Segments) {
		$current = Find-SourcemapChild -Node $current -Name $segment
		Assert-Stage3 -Condition ($null -ne $current) -Message "$Description is missing segment $segment"
	}
	return $current
}

$requiredPaths = @(
	"src/ServerScriptService/Domain/PlotTypes.lua",
	"src/ServerScriptService/Domain/PlotBounds.lua",
	"src/ServerScriptService/Config/PlotConfigValidator.lua",
	"src/ServerScriptService/Systems/PlotRuntimeBuilder.lua",
	"src/ServerScriptService/Services/PlotService.lua",
	"src/ServerScriptService/Services/PlayerSessionService.lua",
	"src/ServerStorage/Config/PlotDefinitions.lua",
	"tests/unit/PlotBoundsSpec.lua",
	"tests/unit/PlotConfigSpec.lua",
	"tests/integration/PlotServiceIntegrationSpec.lua",
	"tests/integration/ProductionPlotRuntimeSpec.lua",
	"tests/serverFixtures/PlotTestUtils.lua",
	"tests/fixtures/TestPlotRemoteDefinitions.lua",
	"tests/ForeignOwnershipProbe.server.lua",
	"tests/ForeignOwnershipProbe.client.lua",
	"docs/STAGE_3_ARCHITECTURE.md"
)
foreach ($relativePath in $requiredPaths) {
	Assert-Stage3 -Condition (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath) -PathType Leaf) -Message "Required path is missing: $relativePath"
}

$productionProjectText = Read-ProjectFile "default.project.json"
$productionProject = $productionProjectText | ConvertFrom-Json
$testProjectText = Read-ProjectFile "test.project.json"
$testProject = $testProjectText | ConvertFrom-Json

Assert-Stage3 -Condition (-not $productionProjectText.Contains("tests/")) -Message "Production project must not map tests"
Assert-Stage3 -Condition (-not (Test-Path -LiteralPath (Join-Path $projectRoot "src/ServerScriptService/Systems/OfficeShellBuilder.lua"))) -Message "Retired OfficeShellBuilder must remain absent"
Assert-Stage3 -Condition ($productionProject.tree.Workspace.'$path' -eq "src/Workspace") -Message "Accepted production Workspace mapping changed"
Assert-Stage3 -Condition ($testProject.tree.ServerScriptService.Domain.'$path' -eq "src/ServerScriptService/Domain") -Message "Test project does not map server plot domain"
Assert-Stage3 -Condition ($testProject.tree.ServerScriptService.Services.'$path' -eq "src/ServerScriptService/Services") -Message "Test project does not map Stage 3 services"
Assert-Stage3 -Condition ($testProject.tree.ServerScriptService.Systems.'$path' -eq "src/ServerScriptService/Systems") -Message "Test project does not map Stage 3 systems"
Assert-Stage3 -Condition ($testProject.tree.ServerScriptService.Stage2Tests.ForeignOwnershipProbe.'$path' -eq "tests/ForeignOwnershipProbe.server.lua") -Message "Test server foreign ownership probe is not mapped"
Assert-Stage3 -Condition ($testProject.tree.StarterPlayer.StarterPlayerScripts.Stage3ForeignOwnershipProbe.'$path' -eq "tests/ForeignOwnershipProbe.client.lua") -Message "Test client foreign ownership probe is not mapped"

$plotDefinitions = Read-ProjectFile "src/ServerStorage/Config/PlotDefinitions.lua"
Assert-Stage3 -Condition ($plotDefinitions.Contains("maxPlayers = 6")) -Message "Approved maxPlayers is missing"
Assert-Stage3 -Condition ($plotDefinitions.Contains("Vector2.new(96, 96)")) -Message "Approved plot footprint is missing"
Assert-Stage3 -Condition ($plotDefinitions.Contains("local MAX_HEIGHT = 64")) -Message "Approved maximum build height is missing"
Assert-Stage3 -Condition ($plotDefinitions.Contains("local CENTER_SPACING = 128")) -Message "Approved center spacing is missing"
Assert-Stage3 -Condition ($plotDefinitions.Contains("plotGap = 32")) -Message "Approved plot gap is missing"
for ($plotIndex = 1; $plotIndex -le 6; $plotIndex += 1) {
	$plotId = "plot_{0:D2}" -f $plotIndex
	Assert-Stage3 -Condition ($plotDefinitions.Contains("`"$plotId`"")) -Message "Stable plot ID is missing: $plotId"
}

$remoteDefinitions = Read-ProjectFile "src/ReplicatedStorage/Shared/Remotes/RemoteDefinitions.lua"
Assert-Stage3 -Condition ($remoteDefinitions.Contains('name = "RequestOfficeCatalog"')) -Message "Approved Stage 4 catalog remote is missing"
Assert-Stage3 -Condition ($remoteDefinitions.Contains('name = "RequestOfficePurchase"')) -Message "Approved Stage 4 purchase remote is missing"
Assert-Stage3 -Condition (-not $remoteDefinitions.Contains("TestPlotMutation")) -Message "Test-only plot remote leaked into production definitions"

$replicatedPlotModules = Get-ChildItem -Path (Join-Path $projectRoot "src/ReplicatedStorage") -Recurse -File | Where-Object {
	$_.Name -in @("PlotTypes.lua", "PlotBounds.lua", "PlotDefinitions.lua")
}
Assert-Stage3 -Condition ($replicatedPlotModules.Count -eq 0) -Message "Stage 3 plot domain must remain server-only"

$plotService = Read-ProjectFile "src/ServerScriptService/Services/PlotService.lua"
$playerSessionService = Read-ProjectFile "src/ServerScriptService/Services/PlayerSessionService.lua"
$plotRuntimeBuilder = Read-ProjectFile "src/ServerScriptService/Systems/PlotRuntimeBuilder.lua"
$officeLayoutBuilder = Read-ProjectFile "src/ServerScriptService/Systems/OfficeLayoutBuilder.lua"
$serverApplication = Read-ProjectFile "src/ServerScriptService/Bootstrap/ServerApplication.lua"
Assert-Stage3 -Condition ($plotService.Contains('ensureFolder(self._workspaceRoot, "Map")')) -Message "PlotService.Init must own canonical Map creation"
Assert-Stage3 -Condition ($plotService.Contains('ensureFolder(mapFolder, "Plots")')) -Message "PlotService.Init must own canonical Plots creation"
Assert-Stage3 -Condition ($serverApplication.Contains('name = "PlotService"')) -Message "PlotService is not registered through ServiceRegistry"
Assert-Stage3 -Condition ($serverApplication.Contains('name = "PlayerSessionService"')) -Message "PlayerSessionService is not registered through ServiceRegistry"
Assert-Stage3 -Condition ($serverApplication.Contains('"PlotService", "SessionCurrencyService", "OfficeBuildingService"')) -Message "PlayerSessionService lacks its explicit Stage 3/4 dependencies"
Assert-Stage3 -Condition ($playerSessionService.Contains("Players.PlayerAdded") -or $playerSessionService.Contains("self._players.PlayerAdded")) -Message "PlayerAdded lifecycle binding is missing"
Assert-Stage3 -Condition ($playerSessionService.Contains("Players.PlayerRemoving") -or $playerSessionService.Contains("self._players.PlayerRemoving")) -Message "PlayerRemoving lifecycle binding is missing"
Assert-Stage3 -Condition ($playerSessionService.Contains("CharacterAdded:Connect")) -Message "CharacterAdded lifecycle binding is missing"
Assert-Stage3 -Condition ($playerSessionService.Contains("CharacterAppearanceLoaded:Connect")) -Message "Lifecycle-ready character binding is missing"
Assert-Stage3 -Condition ($playerSessionService.Contains("WaitForChild(`"HumanoidRootPart`", CHARACTER_ROOT_TIMEOUT_SECONDS)")) -Message "HumanoidRootPart lookup must be bounded"
Assert-Stage3 -Condition ($playerSessionService.Contains("player.RespawnLocation = spawnContext.spawnLocation")) -Message "Authoritative RespawnLocation binding is missing"
Assert-Stage3 -Condition ($playerSessionService.Contains("player.RespawnLocation = nil")) -Message "RespawnLocation cleanup is missing"
Assert-Stage3 -Condition ($playerSessionService.Contains("spawnContext.generationToken ~= session.generationToken")) -Message "Spawn callback generation-token validation is missing"
Assert-Stage3 -Condition (-not $playerSessionService.Contains("LoadCharacter")) -Message "Production session service must retain automatic character spawning"
Assert-Stage3 -Condition ($plotRuntimeBuilder.Contains('Instance.new("SpawnLocation")')) -Message "Physical plot spawn must be a SpawnLocation"
Assert-Stage3 -Condition ($plotRuntimeBuilder.Contains('"PlotAnchor"')) -Message "Stable PlotAnchor is missing"
Assert-Stage3 -Condition ($plotRuntimeBuilder.Contains('"PlotBoundary"')) -Message "PlotBoundary is missing"
Assert-Stage3 -Condition ($plotRuntimeBuilder.Contains('"SpawnMarker"')) -Message "SpawnMarker is missing"
Assert-Stage3 -Condition ($plotRuntimeBuilder.Contains("plotModel.PrimaryPart = anchor")) -Message "PlotRuntimeModel PrimaryPart must be PlotAnchor"
Assert-Stage3 -Condition (([regex]::Matches($plotRuntimeBuilder, 'Instance.new\("SpawnLocation"\)')).Count -eq 1) -Message "Plot runtime builder must create exactly one spawn"
Assert-Stage3 -Condition (([regex]::Matches($plotRuntimeBuilder, '"PlotAnchor"')).Count -eq 1) -Message "Plot runtime builder must create exactly one PlotAnchor"
Assert-Stage3 -Condition (-not $plotRuntimeBuilder.Contains('"SpawnPlatform"')) -Message "Legacy non-spawn Part must not remain canonical"
Assert-Stage3 -Condition (-not $officeLayoutBuilder.Contains('Instance.new("SpawnLocation")')) -Message "Stage 4 office builder must not create a second spawn"
Assert-Stage3 -Condition (-not $officeLayoutBuilder.Contains('"PlotAnchor"')) -Message "Stage 4 office builder must not create or replace PlotAnchor"

$stage3ProductionFiles = @(
	"src/ServerScriptService/Domain/PlotTypes.lua",
	"src/ServerScriptService/Domain/PlotBounds.lua",
	"src/ServerScriptService/Config/PlotConfigValidator.lua",
	"src/ServerScriptService/Systems/PlotRuntimeBuilder.lua",
	"src/ServerScriptService/Services/PlotService.lua",
	"src/ServerScriptService/Services/PlayerSessionService.lua",
	"src/ServerStorage/Config/PlotDefinitions.lua"
)
foreach ($relativePath in $stage3ProductionFiles) {
	$content = Read-ProjectFile $relativePath
	Assert-Stage3 -Condition ($content.StartsWith("--!strict")) -Message "Strict mode is missing from $relativePath"
	Assert-Stage3 -Condition (-not $content.Contains(".Touched")) -Message "Touched must not be a Stage 3 security mechanism: $relativePath"
	Assert-Stage3 -Condition (-not $content.Contains("RenderStepped")) -Message "Stage 3 must not add a per-frame RenderStepped loop: $relativePath"
	Assert-Stage3 -Condition (-not $content.Contains("Heartbeat")) -Message "Stage 3 must not add a per-frame Heartbeat loop: $relativePath"
	Assert-Stage3 -Condition (-not $content.Contains("while true")) -Message "Stage 3 must not add an unbounded loop: $relativePath"
}

$productionSourcemapPath = [System.IO.Path]::GetTempFileName()
$testSourcemapPath = [System.IO.Path]::GetTempFileName()
try {
	& rojo sourcemap (Join-Path $projectRoot "default.project.json") --output $productionSourcemapPath | Out-Host
	if ($LASTEXITCODE -ne 0) {
		throw "Production rojo sourcemap failed with exit code $LASTEXITCODE"
	}
	& rojo sourcemap (Join-Path $projectRoot "test.project.json") --output $testSourcemapPath | Out-Host
	if ($LASTEXITCODE -ne 0) {
		throw "Test rojo sourcemap failed with exit code $LASTEXITCODE"
	}

	$productionSourcemap = Get-Content -Raw -LiteralPath $productionSourcemapPath | ConvertFrom-Json
	$testSourcemap = Get-Content -Raw -LiteralPath $testSourcemapPath | ConvertFrom-Json
	$null = Assert-SourcemapPath -Root $productionSourcemap -Segments @("ServerScriptService", "Domain", "PlotBounds") -Description "Production PlotBounds"
	$null = Assert-SourcemapPath -Root $productionSourcemap -Segments @("ServerScriptService", "Services", "PlotService") -Description "Production PlotService"
	$null = Assert-SourcemapPath -Root $productionSourcemap -Segments @("ServerScriptService", "Services", "PlayerSessionService") -Description "Production PlayerSessionService"
	$null = Assert-SourcemapPath -Root $productionSourcemap -Segments @("ServerScriptService", "Systems", "PlotRuntimeBuilder") -Description "Production PlotRuntimeBuilder"
	$null = Assert-SourcemapPath -Root $productionSourcemap -Segments @("ServerStorage", "Config", "PlotDefinitions") -Description "Production PlotDefinitions"
	Assert-Stage3 -Condition ($productionSourcemapPath -ne $testSourcemapPath) -Message "Production and test sourcemaps must be separate"
	Assert-Stage3 -Condition (-not (Get-Content -Raw -LiteralPath $productionSourcemapPath).Contains("TestPlotRemoteDefinitions")) -Message "Test-only plot remote definition leaked into production sourcemap"
	Assert-Stage3 -Condition (-not (Get-Content -Raw -LiteralPath $productionSourcemapPath).Contains("ForeignOwnershipProbe")) -Message "Foreign ownership probe leaked into production sourcemap"
	$null = Assert-SourcemapPath -Root $testSourcemap -Segments @("ReplicatedStorage", "TestSupport", "TestPlotRemoteDefinitions") -Description "Test-only plot remote definition"
	$null = Assert-SourcemapPath -Root $testSourcemap -Segments @("ServerScriptService", "Stage2Tests", "ForeignOwnershipProbe") -Description "Test server foreign ownership probe"
	$null = Assert-SourcemapPath -Root $testSourcemap -Segments @("StarterPlayer", "StarterPlayerScripts", "Stage3ForeignOwnershipProbe") -Description "Test client foreign ownership probe"
}
finally {
	Remove-Item -LiteralPath $productionSourcemapPath -Force -ErrorAction SilentlyContinue
	Remove-Item -LiteralPath $testSourcemapPath -Force -ErrorAction SilentlyContinue
}

Write-Host "Stage 3 structural tests passed ($script:assertionCount assertions)."
