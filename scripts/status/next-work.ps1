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
$files = Get-ChildItem -LiteralPath $TodoRoot -File -Filter '*.md' | Sort-Object Name
$openItemCount = 0
$completedItemCount = 0

foreach ($file in $files) {
    $heading = ''
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $file.FullName) {
        $lineNumber++
        if ($line -match '^#\s+(.+)$') {
            $heading = $Matches[1]
        }
        if ($line -match '^- \[ \]\s+(.+)$') {
            $openItemCount++
            if (-not $firstOpen) {
                $firstOpen = [ordered]@{
                    status = 'open'
                    file = $file.FullName
                    line = $lineNumber
                    heading = $heading
                    task = $Matches[1]
                }
            }
        }
        elseif ($line -match '^- \[x\]\s+(.+)$') {
            $completedItemCount++
        }
    }
}

$todoSummary = [ordered]@{
    todoRoot = (Resolve-Path -LiteralPath $TodoRoot).Path
    todoFileCount = @($files).Count
    checkedItemCount = $openItemCount + $completedItemCount
    openItemCount = $openItemCount
    completedItemCount = $completedItemCount
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

foreach ($key in $todoSummary.Keys) {
    $firstOpen[$key] = $todoSummary[$key]
}

if ($Markdown) {
    if ($firstOpen.status -eq 'open') {
        Write-Output ("Next open TODO: {0}" -f $firstOpen.task)
        Write-Output ("File: {0}:{1}" -f $firstOpen.file, $firstOpen.line)
        Write-Output ("Section: {0}" -f $firstOpen.heading)
        Write-Output ("Backlog: {0} open / {1} checked items across {2} files" -f $firstOpen.openItemCount, $firstOpen.checkedItemCount, $firstOpen.todoFileCount)
    }
    else {
        Write-Output $firstOpen.task
        Write-Output ("Backlog complete: {0} checked items across {1} files" -f $firstOpen.checkedItemCount, $firstOpen.todoFileCount)
    }
}
else {
    $firstOpen | ConvertTo-Json -Depth 4
}

exit 0
