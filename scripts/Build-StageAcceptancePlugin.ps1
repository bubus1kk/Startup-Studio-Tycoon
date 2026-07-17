[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildDirectory = Join-Path $projectRoot "build"
$outputPath = Join-Path $buildDirectory "StageAcceptancePlugin.rbxm"

if (-not (Test-Path -LiteralPath $buildDirectory -PathType Container)) {
	New-Item -ItemType Directory -Path $buildDirectory | Out-Null
}

& rojo build (Join-Path $projectRoot "stage-acceptance-plugin.project.json") -o $outputPath
if ($LASTEXITCODE -ne 0) {
	throw "Stage Acceptance Plugin build failed with exit code $LASTEXITCODE"
}

Write-Host "Built local Studio plugin: $outputPath"
Write-Host "The script did not install or copy the plugin. Install it manually in Roblox Studio after review."
