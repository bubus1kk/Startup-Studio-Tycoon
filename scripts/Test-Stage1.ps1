[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$script:assertionCount = 0

function Assert-Stage1 {
	param(
		[Parameter(Mandatory = $true)]
		[bool]$Condition,

		[Parameter(Mandatory = $true)]
		[string]$Message
	)

	$script:assertionCount += 1
	if (-not $Condition) {
		throw "Stage 1 assertion failed: $Message"
	}
}

$requiredPaths = @(
	"default.project.json",
	"rokit.toml",
	"stylua.toml",
	"selene.toml",
	".gitignore",
	"AGENTS.md",
	".agents/skills",
	".github/workflows/ci.yml",
	"src/ReplicatedStorage",
	"src/ServerScriptService",
	"src/ServerStorage",
	"src/StarterPlayer/StarterPlayerScripts",
	"src/StarterGui",
	"src/Workspace",
	"tests/unit",
	"tests/integration",
	"tests/fixtures"
)

foreach ($relativePath in $requiredPaths) {
	$absolutePath = Join-Path $projectRoot $relativePath
	Assert-Stage1 -Condition (Test-Path -LiteralPath $absolutePath) -Message "Required path is missing: $relativePath"
}

$rokitManifest = Get-Content -Raw -LiteralPath (Join-Path $projectRoot "rokit.toml")
$requiredToolPins = @(
	'rojo = "rojo-rbx/rojo@7.7.0"',
	'stylua = "JohnnyMorganz/StyLua@2.5.2"',
	'selene = "Kampfkarren/selene@0.31.0"',
	'wally = "UpliftGames/wally@0.3.2"'
)

foreach ($toolPin in $requiredToolPins) {
	Assert-Stage1 -Condition ($rokitManifest.Contains($toolPin)) -Message "Pinned tool is missing from rokit.toml: $toolPin"
}

$projectFile = Join-Path $projectRoot "default.project.json"
$project = Get-Content -Raw -LiteralPath $projectFile | ConvertFrom-Json

Assert-Stage1 -Condition ($project.name -eq "StartupStudioTycoon") -Message "Rojo project name is incorrect"
Assert-Stage1 -Condition ($project.tree.'$className' -eq "DataModel") -Message "Rojo root must be a DataModel"
Assert-Stage1 -Condition ($project.tree.ReplicatedStorage.'$path' -eq "src/ReplicatedStorage") -Message "ReplicatedStorage mapping is incorrect"
Assert-Stage1 -Condition ($project.tree.ServerScriptService.'$path' -eq "src/ServerScriptService") -Message "ServerScriptService mapping is incorrect"
Assert-Stage1 -Condition ($project.tree.ServerStorage.'$path' -eq "src/ServerStorage") -Message "ServerStorage mapping is incorrect"
Assert-Stage1 -Condition ($project.tree.StarterPlayer.StarterPlayerScripts.'$path' -eq "src/StarterPlayer/StarterPlayerScripts") -Message "StarterPlayerScripts mapping is incorrect"
Assert-Stage1 -Condition ($project.tree.StarterGui.'$path' -eq "src/StarterGui") -Message "StarterGui mapping is incorrect"
Assert-Stage1 -Condition ($project.tree.Workspace.'$path' -eq "src/Workspace") -Message "Workspace mapping is incorrect"

$serverBootstrap = Join-Path $projectRoot "src/ServerScriptService/Bootstrap/Bootstrap.server.lua"
$clientBootstrap = Join-Path $projectRoot "src/StarterPlayer/StarterPlayerScripts/Bootstrap/Bootstrap.client.lua"

Assert-Stage1 -Condition (Test-Path -LiteralPath $serverBootstrap -PathType Leaf) -Message "Server bootstrap is missing"
Assert-Stage1 -Condition (Test-Path -LiteralPath $clientBootstrap -PathType Leaf) -Message "Client bootstrap is missing"

$luauFiles = Get-ChildItem -Path (Join-Path $projectRoot "src") -Recurse -File -Filter "*.lua"
Assert-Stage1 -Condition ($luauFiles.Count -gt 0) -Message "No Luau source files were found"

foreach ($luauFile in $luauFiles) {
	$content = Get-Content -Raw -LiteralPath $luauFile.FullName
	$relativePath = [System.IO.Path]::GetRelativePath($projectRoot, $luauFile.FullName)
	Assert-Stage1 -Condition ($content.StartsWith("--!strict")) -Message "Strict mode is missing from $relativePath"
}

Write-Host "Stage 1 structural tests passed ($script:assertionCount assertions)."
