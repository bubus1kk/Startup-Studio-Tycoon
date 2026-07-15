[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$script:assertionCount = 0

function Assert-Stage2 {
	param(
		[Parameter(Mandatory = $true)]
		[bool]$Condition,

		[Parameter(Mandatory = $true)]
		[string]$Message
	)

	$script:assertionCount += 1
	if (-not $Condition) {
		throw "Stage 2 assertion failed: $Message"
	}
}

function Read-ProjectFile {
	param(
		[Parameter(Mandatory = $true)]
		[string]$RelativePath
	)

	return Get-Content -Raw -LiteralPath (Join-Path $projectRoot $RelativePath)
}

$requiredPaths = @(
	"test.project.json",
	"src/ReplicatedStorage/Shared/Config/ConfigLoader.lua",
	"src/ReplicatedStorage/Shared/Config/PublicFeatureFlags.lua",
	"src/ReplicatedStorage/Shared/Infrastructure/ClientDependencyResolver.lua",
	"src/ReplicatedStorage/Shared/Infrastructure/LifecycleRegistry.lua",
	"src/ReplicatedStorage/Shared/Infrastructure/Logger.lua",
	"src/ReplicatedStorage/Shared/Remotes/RemoteDefinitions.lua",
	"src/ReplicatedStorage/Shared/Remotes/RemoteTypes.lua",
	"src/ReplicatedStorage/Shared/Validation/PayloadValidator.lua",
	"src/ServerScriptService/Infrastructure/ServiceRegistry.lua",
	"src/ServerScriptService/Infrastructure/ServerRemoteRegistry.lua",
	"src/ServerScriptService/Bootstrap/ServerApplication.lua",
	"src/ServerStorage/Config/ServerConfig.lua",
	"src/StarterPlayer/StarterPlayerScripts/Infrastructure/ControllerRegistry.lua",
	"src/StarterPlayer/StarterPlayerScripts/Infrastructure/RemoteClient.lua",
	"src/StarterPlayer/StarterPlayerScripts/Bootstrap/ClientApplication.lua",
	"tests/TestRunner.server.lua",
	"tests/TestClient.client.lua",
	"tests/fixtures/TestRemoteDefinitions.lua",
	"tests/unit/ClientDependencyResolverSpec.lua",
	"tests/unit/LifecycleRegistrySpec.lua",
	"tests/integration/RemoteRegistryIntegrationSpec.lua"
)

foreach ($relativePath in $requiredPaths) {
	Assert-Stage2 -Condition (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath) -PathType Leaf) -Message "Required path is missing: $relativePath"
}

$productionProjectText = Read-ProjectFile "default.project.json"
$productionProject = $productionProjectText | ConvertFrom-Json
$testProject = (Read-ProjectFile "test.project.json") | ConvertFrom-Json

Assert-Stage2 -Condition (-not $productionProjectText.Contains("tests/")) -Message "Production project must not map test files"
Assert-Stage2 -Condition ($null -eq $productionProject.tree.ReplicatedStorage.TestSupport) -Message "Production project must not expose TestSupport"
Assert-Stage2 -Condition ($testProject.tree.ReplicatedStorage.TestSupport.'$path' -eq "tests/fixtures") -Message "Test-only remote definitions must be mapped only by test.project.json"
Assert-Stage2 -Condition ($testProject.tree.ServerScriptService.Stage2Tests.Integration.'$path' -eq "tests/integration") -Message "Integration tests are not mapped in test.project.json"
Assert-Stage2 -Condition ($testProject.tree.StarterPlayer.StarterPlayerScripts.Stage2TestClient.'$path' -eq "tests/TestClient.client.lua") -Message "Test client is not mapped in test.project.json"

$tempProductionSourcemap = [System.IO.Path]::GetTempFileName()
try {
	& rojo sourcemap (Join-Path $projectRoot "default.project.json") --output $tempProductionSourcemap | Out-Host
	if ($LASTEXITCODE -ne 0) {
		throw "rojo sourcemap failed with exit code $LASTEXITCODE"
	}

	$productionSourcemap = Get-Content -Raw -LiteralPath $tempProductionSourcemap | ConvertFrom-Json
	$starterPlayerNode = $productionSourcemap.children | Where-Object { $_.name -eq "StarterPlayer" }
	$starterPlayerScriptsNode = $starterPlayerNode.children | Where-Object { $_.name -eq "StarterPlayerScripts" }
	$clientInfrastructureNode = $starterPlayerScriptsNode.children | Where-Object { $_.name -eq "Infrastructure" }
	$clientBootstrapNode = $starterPlayerScriptsNode.children | Where-Object { $_.name -eq "Bootstrap" }

	Assert-Stage2 -Condition ($null -ne $clientInfrastructureNode) -Message "Production sourcemap is missing StarterPlayerScripts.Infrastructure"
	Assert-Stage2 -Condition ($null -ne ($clientInfrastructureNode.children | Where-Object { $_.name -eq "ControllerRegistry" -and $_.className -eq "ModuleScript" })) -Message "Production sourcemap is missing client ControllerRegistry"
	Assert-Stage2 -Condition ($null -ne ($clientInfrastructureNode.children | Where-Object { $_.name -eq "RemoteClient" -and $_.className -eq "ModuleScript" })) -Message "Production sourcemap is missing client RemoteClient"
	Assert-Stage2 -Condition ($null -ne ($clientBootstrapNode.children | Where-Object { $_.name -eq "ClientApplication" -and $_.className -eq "ModuleScript" })) -Message "Production sourcemap is missing ClientApplication"
}
finally {
	Remove-Item -LiteralPath $tempProductionSourcemap -Force -ErrorAction SilentlyContinue
}

$sharedRemoteFiles = @(
	"src/ReplicatedStorage/Shared/Remotes/RemoteDefinitions.lua",
	"src/ReplicatedStorage/Shared/Remotes/RemoteTypes.lua",
	"src/ReplicatedStorage/Shared/Remotes/RemoteDefinitionValidator.lua"
)
foreach ($relativePath in $sharedRemoteFiles) {
	$content = Read-ProjectFile $relativePath
	Assert-Stage2 -Condition (-not $content.Contains("Instance.new")) -Message "Shared remote module creates Instances: $relativePath"
	Assert-Stage2 -Condition (-not $content.Contains("OnServerEvent")) -Message "Shared remote module contains server bindings: $relativePath"
	Assert-Stage2 -Condition (-not $content.Contains("OnServerInvoke")) -Message "Shared remote module contains server function bindings: $relativePath"
}

$serverRemoteRegistry = Read-ProjectFile "src/ServerScriptService/Infrastructure/ServerRemoteRegistry.lua"
$remoteClient = Read-ProjectFile "src/StarterPlayer/StarterPlayerScripts/Infrastructure/RemoteClient.lua"
Assert-Stage2 -Condition ($serverRemoteRegistry.Contains('Instance.new("RemoteEvent")')) -Message "ServerRemoteRegistry must own RemoteEvent creation"
Assert-Stage2 -Condition ($serverRemoteRegistry.Contains('Instance.new("RemoteFunction")')) -Message "ServerRemoteRegistry must own RemoteFunction creation"
Assert-Stage2 -Condition (-not $remoteClient.Contains('Instance.new("RemoteEvent")')) -Message "Client must never create RemoteEvents"
Assert-Stage2 -Condition (-not $remoteClient.Contains('Instance.new("RemoteFunction")')) -Message "Client must never create RemoteFunctions"

$remoteDefinitions = Read-ProjectFile "src/ReplicatedStorage/Shared/Remotes/RemoteDefinitions.lua"
Assert-Stage2 -Condition ($remoteDefinitions.Contains("local definitions: { RemoteDefinition } = {}")) -Message "Production remote definitions must remain empty in Stage 2"

$serviceRegistry = Read-ProjectFile "src/ServerScriptService/Infrastructure/ServiceRegistry.lua"
$controllerRegistry = Read-ProjectFile "src/StarterPlayer/StarterPlayerScripts/Infrastructure/ControllerRegistry.lua"
Assert-Stage2 -Condition ($serviceRegistry.Contains("Shared.Infrastructure.LifecycleRegistry")) -Message "ServiceRegistry must delegate to the shared lifecycle engine"
Assert-Stage2 -Condition ($controllerRegistry.Contains("Shared.Infrastructure.LifecycleRegistry")) -Message "ControllerRegistry must delegate to the shared lifecycle engine"
Assert-Stage2 -Condition (-not $serviceRegistry.Contains("ResolveStartupOrder")) -Message "ServiceRegistry must not duplicate dependency resolution"
Assert-Stage2 -Condition (-not $controllerRegistry.Contains("ResolveStartupOrder")) -Message "ControllerRegistry must not duplicate dependency resolution"

$lifecycleRegistry = Read-ProjectFile "src/ReplicatedStorage/Shared/Infrastructure/LifecycleRegistry.lua"
Assert-Stage2 -Condition ($lifecycleRegistry.Contains("DuplicateLifecycleObject")) -Message "Duplicate lifecycle registrations must be rejected"
Assert-Stage2 -Condition ($lifecycleRegistry.Contains("MissingLifecycleDependency")) -Message "Missing lifecycle dependencies must be reported"
Assert-Stage2 -Condition ($lifecycleRegistry.Contains("LifecycleDependencyCycle")) -Message "Lifecycle dependency cycles must be reported"
Assert-Stage2 -Condition ($lifecycleRegistry.Contains("table.sort(ready)")) -Message "Independent lifecycle nodes must use a deterministic tie-breaker"
Assert-Stage2 -Condition ($lifecycleRegistry.Contains("LifecycleCleanupFailed")) -Message "Cleanup failures must have a distinct diagnostic code"
Assert-Stage2 -Condition ($lifecycleRegistry.Contains("for index = #self._initialized, 1, -1")) -Message "Lifecycle cleanup must run in reverse initialized order"
Assert-Stage2 -Condition ($lifecycleRegistry.Contains('if self._state == "Destroyed"')) -Message "DestroyAll must be idempotent"

$remoteDefinitionValidator = Read-ProjectFile "src/ReplicatedStorage/Shared/Remotes/RemoteDefinitionValidator.lua"
Assert-Stage2 -Condition ($remoteDefinitionValidator.Contains("DuplicateRemoteDefinition")) -Message "Duplicate remote definitions must be rejected"
Assert-Stage2 -Condition ($serverRemoteRegistry.Contains("DuplicateRemoteBinding")) -Message "Duplicate server remote bindings must be rejected"

$deepFreeze = Read-ProjectFile "src/ReplicatedStorage/Shared/Utils/DeepFreeze.lua"
$configLoader = Read-ProjectFile "src/ReplicatedStorage/Shared/Config/ConfigLoader.lua"
Assert-Stage2 -Condition ($deepFreeze.Contains("table.freeze(copy)")) -Message "Validated configs must be recursively frozen"
Assert-Stage2 -Condition ($configLoader.Contains("DeepFreeze.copy")) -Message "ConfigLoader must copy config values before publishing them"

$clientBootstrap = Read-ProjectFile "src/StarterPlayer/StarterPlayerScripts/Bootstrap/Bootstrap.client.lua"
Assert-Stage2 -Condition (-not $clientBootstrap.Contains("game:BindToClose")) -Message "Client bootstrap must not invent a BindToClose equivalent"
Assert-Stage2 -Condition ($clientBootstrap.Contains("waitForModuleScript")) -Message "Client bootstrap must use bounded lookup for ClientApplication"

$clientApplication = Read-ProjectFile "src/StarterPlayer/StarterPlayerScripts/Bootstrap/ClientApplication.lua"
$clientDependencyResolver = Read-ProjectFile "src/ReplicatedStorage/Shared/Infrastructure/ClientDependencyResolver.lua"
$testClient = Read-ProjectFile "tests/TestClient.client.lua"
Assert-Stage2 -Condition ($clientApplication.Contains("resolvePlayerScripts")) -Message "ClientApplication must resolve runtime-copied dependencies before requiring them"
Assert-Stage2 -Condition ($clientApplication.Contains("CLIENT_DEPENDENCY_TIMEOUT_SECONDS = 10")) -Message "Client dependency lookup must have the approved bounded timeout"
Assert-Stage2 -Condition ($clientDependencyResolver.Contains("StartupDependencyTimeout")) -Message "Client dependency timeout must use a stable StartupError code"
Assert-Stage2 -Condition ($clientDependencyResolver.Contains("PlayerScripts.Infrastructure.ControllerRegistry")) -Message "ControllerRegistry must be resolved explicitly"
Assert-Stage2 -Condition ($clientDependencyResolver.Contains("PlayerScripts.Infrastructure.RemoteClient")) -Message "RemoteClient must be resolved explicitly"
Assert-Stage2 -Condition ($clientApplication.Contains('self._logger:Info("client_bootstrap_ready"')) -Message "ClientApplication must emit client_bootstrap_ready before reporting success"
Assert-Stage2 -Condition ($testClient.Contains('bootstrapState ~= "Ready"')) -Message "Test client must reject a failed production client bootstrap"
Assert-Stage2 -Condition ($testClient.Contains("PASS production client emitted client_bootstrap_ready")) -Message "Test session must prove production client bootstrap readiness"

$serverOnlyPaths = @(
	"src/ServerStorage/Config/ServerConfig.lua",
	"src/ServerScriptService/Infrastructure/RuntimeEnvironment.lua",
	"src/ServerScriptService/Infrastructure/ServerRemoteRegistry.lua"
)
foreach ($relativePath in $serverOnlyPaths) {
	Assert-Stage2 -Condition (-not $productionProject.tree.ReplicatedStorage.'$path'.Contains((Split-Path $relativePath -Parent))) -Message "Server-only path is replicated: $relativePath"
}

$luauFiles = Get-ChildItem -Path (Join-Path $projectRoot "src"), (Join-Path $projectRoot "tests") -Recurse -File -Filter "*.lua"
foreach ($luauFile in $luauFiles) {
	$content = Get-Content -Raw -LiteralPath $luauFile.FullName
	$relativePath = [System.IO.Path]::GetRelativePath($projectRoot, $luauFile.FullName)
	Assert-Stage2 -Condition ($content.StartsWith("--!strict")) -Message "Strict mode is missing from $relativePath"
}

Write-Host "Stage 2 structural tests passed ($script:assertionCount assertions)."
