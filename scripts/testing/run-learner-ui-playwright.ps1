[CmdletBinding()]
param(
    [switch]$KeepArtifacts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (& git -C . rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repo)) {
    throw 'Unable to resolve repository root with git.'
}

$runId = ('learner-ui-playwright_{0:yyyyMMdd_HHmmss}_{1}' -f (Get-Date), [Guid]::NewGuid().ToString('N').Substring(0, 8))
$cacheRoot = Join-Path $repo '.codex-cache'
$logRoot = Join-Path $cacheRoot 'logs'
$tmpRoot = Join-Path (Join-Path $cacheRoot 'tmp') $runId
$artifactRoot = Join-Path $tmpRoot 'artifacts'
$logPath = Join-Path $logRoot "$runId.log"

[void](New-Item -ItemType Directory -Force -Path $logRoot, $artifactRoot)

$previousTemp = $env:TEMP
$previousTmp = $env:TMP
$previousOutputDir = $env:PLAYWRIGHT_OUTPUT_DIR
$exitCode = 1
$pushed = $false

try {
    $env:TEMP = $tmpRoot
    $env:TMP = $tmpRoot
    $env:PLAYWRIGHT_OUTPUT_DIR = $artifactRoot

    Push-Location $repo
    $pushed = $true

    "learner-ui-playwright start run=$runId" | Tee-Object -FilePath $logPath -Append

    if (-not (Test-Path -LiteralPath '.\node_modules\.bin\playwright.ps1' -PathType Leaf)) {
        throw 'Playwright is not installed. Run npm install first.'
    }

    & .\node_modules\.bin\playwright.ps1 test --config .\playwright.config.js 2>&1 | Tee-Object -FilePath $logPath -Append
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        "learner-ui-playwright passed log=$logPath" | Tee-Object -FilePath $logPath -Append
    }
    else {
        "learner-ui-playwright failed exit=$exitCode log=$logPath artifacts=$artifactRoot" | Tee-Object -FilePath $logPath -Append
    }
}
catch {
    ("learner-ui-playwright error: " + $_.Exception.Message) | Tee-Object -FilePath $logPath -Append
    $exitCode = 1
}
finally {
    if ($pushed) {
        Pop-Location
    }

    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
    $env:PLAYWRIGHT_OUTPUT_DIR = $previousOutputDir

    if (-not $KeepArtifacts -and (Test-Path -LiteralPath $tmpRoot)) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force
    }
}

exit $exitCode
