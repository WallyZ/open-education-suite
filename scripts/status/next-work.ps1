[CmdletBinding()]
param(
    [string]$TodoRoot = '.\docs\todo',
    [switch]$Markdown
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $TodoRoot -PathType Container)) {
    throw "TODO root not found: $TodoRoot"
}

$firstOpen = $null
$files = Get-ChildItem -LiteralPath $TodoRoot -File -Filter 'TODO_*.md' | Sort-Object Name

foreach ($file in $files) {
    $heading = ''
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $file.FullName) {
        $lineNumber++
        if ($line -match '^#\s+(.+)$') {
            $heading = $Matches[1]
        }
        if ($line -match '^- \[ \]\s+(.+)$') {
            $firstOpen = [ordered]@{
                status = 'open'
                file = $file.FullName
                line = $lineNumber
                heading = $heading
                task = $Matches[1]
            }
            break
        }
    }
    if ($firstOpen) {
        break
    }
}

if (-not $firstOpen) {
    $firstOpen = [ordered]@{
        status = 'none'
        file = $null
        line = $null
        heading = $null
        task = 'No unchecked TODO items found.'
    }
}

if ($Markdown) {
    if ($firstOpen.status -eq 'open') {
        Write-Output ("Next open TODO: {0}" -f $firstOpen.task)
        Write-Output ("File: {0}:{1}" -f $firstOpen.file, $firstOpen.line)
        Write-Output ("Section: {0}" -f $firstOpen.heading)
    }
    else {
        Write-Output $firstOpen.task
    }
}
else {
    $firstOpen | ConvertTo-Json -Depth 4
}

exit 0
