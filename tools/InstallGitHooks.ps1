$ErrorActionPreference = 'Stop'

$HookDir = Join-Path (Get-Location) '.git\hooks'
$HookPath = Join-Path $HookDir 'pre-commit'

if (-not (Test-Path $HookDir)) {
  throw 'Git hooks folder was not found. Run this script at the repository root.'
}

$Hook = @'
#!/bin/sh
powershell -ExecutionPolicy Bypass -File tools/EnsureUtf8Bom.ps1 -Check
'@

$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$Hook = $Hook -replace "`r?`n", "`n"
[System.IO.File]::WriteAllText($HookPath, $Hook, $Utf8NoBom)
Write-Host "installed pre-commit hook: $HookPath"

