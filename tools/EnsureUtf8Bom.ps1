param(
  [switch]$Check
)

$ErrorActionPreference = 'Stop'
$Utf8Bom = [System.Text.UTF8Encoding]::new($true)
$Utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$Cp932 = [System.Text.Encoding]::GetEncoding(932)
$Targets = @('*.pas', '*.dfm', '*.dpr', '*.dproj', '*.inc', '*.rc', '*.md', '*.txt', '*.bat', '*.cmd', '*.ps1')

function Test-Utf8Bom {
  param([byte[]]$Bytes)
  return $Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF
}

function Read-TextFile {
  param([string]$Path, [byte[]]$Bytes)
  if (Test-Utf8Bom $Bytes) {
    return [System.IO.File]::ReadAllText($Path, $Utf8Bom)
  }

  try {
    return $Utf8Strict.GetString($Bytes)
  } catch {
    return $Cp932.GetString($Bytes)
  }
}

$Files = git ls-files @Targets
$Failed = @()

foreach ($File in $Files) {
  $Bytes = [System.IO.File]::ReadAllBytes($File)
  if (Test-Utf8Bom $Bytes) {
    continue
  }

  if ($Check) {
    $Failed += $File
    continue
  }

  $Text = Read-TextFile $File $Bytes
  $Text = $Text -replace "`r?`n", "`r`n"
  [System.IO.File]::WriteAllText($File, $Text, $Utf8Bom)
  Write-Host "converted UTF-8 BOM: $File"
}

if ($Failed.Count -gt 0) {
  Write-Error ("Files are not UTF-8 BOM:`n" + ($Failed -join "`n"))
}
