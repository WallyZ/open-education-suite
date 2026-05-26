[CmdletBinding()]
param(
    [string]$QaLiveRoot = 'F:\dev\qa-live-test-system',
    [switch]$KeepArtifacts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (& git -C . rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repo)) {
    throw 'Unable to resolve repository root with git.'
}

$runId = ('{0:yyyyMMdd_HHmmss}_{1}' -f (Get-Date), [Guid]::NewGuid().ToString('N').Substring(0, 8))
$cacheRoot = Join-Path $repo '.codex-cache'
$logRoot = Join-Path $cacheRoot 'logs'
$tmpRoot = Join-Path (Join-Path $cacheRoot 'tmp') $runId
$artifactsRoot = Join-Path $tmpRoot 'qa-live-learner-ui'
$summaryPath = Join-Path $artifactsRoot 'summary.json'
$summaryLogPath = Join-Path $logRoot ("qa-live-learner-ui_{0}_summary.json" -f $runId)
$logPath = Join-Path $logRoot ("qa-live-learner-ui_{0}.log" -f $runId)

[void](New-Item -ItemType Directory -Force -Path $logRoot, $tmpRoot, $artifactsRoot)

$previousTemp = $env:TEMP
$previousTmp = $env:TMP
$exitCode = 1

function Write-QALog {
    param([string]$Message)
    $Message | Tee-Object -FilePath $script:logPath -Append
}

function Assert-FileExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing file: $Path"
    }
    Write-QALog "ok file $Path"
}

try {
    $env:TEMP = $tmpRoot
    $env:TMP = $tmpRoot

    $qaPython = Join-Path $QaLiveRoot '.venv\Scripts\python.exe'
    $workflowPath = Join-Path $repo 'qa-live\workflow.learner_ui_live.json'

    Assert-FileExists $qaPython
    Assert-FileExists $workflowPath
    Assert-FileExists (Join-Path $repo 'qa-live\feature_spec.learner_ui_lecture.json')
    Assert-FileExists (Join-Path $repo 'qa-live\capture.learner_ui_static.json')
    Assert-FileExists (Join-Path $repo 'node_modules\@playwright\test\package.json')

    Write-QALog "qa-live learner UI workflow start repo=$repo qaLiveRoot=$QaLiveRoot"
    & $qaPython -m qa_live_test_system.cli workflow-run $workflowPath `
        --repo-root $repo `
        --artifacts-root $artifactsRoot `
        --out $summaryPath `
        --allow-host-execution 2>&1 | Tee-Object -FilePath $logPath -Append
    if (Test-Path -LiteralPath $summaryPath -PathType Leaf) {
        Copy-Item -LiteralPath $summaryPath -Destination $summaryLogPath -Force
    }
    if ($LASTEXITCODE -ne 0) {
        throw "qa-live workflow failed with exit code $LASTEXITCODE."
    }

    Assert-FileExists $summaryPath

    $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
    if ($summary.status -ne 'pass') {
        throw "qa-live workflow reported status '$($summary.status)'."
    }

    Write-QALog "qa-live learner UI workflow passed log=$logPath summary=$summaryLogPath"
    $exitCode = 0
}
catch {
    Write-QALog ("qa-live learner UI workflow error: " + $_.Exception.Message)
    $exitCode = 1
}
finally {
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp

    if (-not $KeepArtifacts -and (Test-Path -LiteralPath $tmpRoot)) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force
    }
}

if ($exitCode -ne 0) {
    Write-Output ("qa-live learner UI workflow failed: exit={0} log={1}" -f $exitCode, $logPath)
    exit $exitCode
}

Write-Output ("qa-live learner UI workflow passed: log={0} summary={1}" -f $logPath, $summaryLogPath)
exit 0
