[CmdletBinding()]
param(
    [switch]$KeepArtifacts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. .\scripts\teaching\lecture-paths.ps1

$repo = (& git -C . rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repo)) {
    throw 'Unable to resolve repository root with git.'
}

$runId = ('lecture-production-smoke_{0:yyyyMMdd_HHmmss}_{1}' -f (Get-Date), [Guid]::NewGuid().ToString('N').Substring(0, 8))
$cacheRoot = Join-Path $repo '.codex-cache'
$logRoot = Join-Path $cacheRoot 'logs'
$tmpRoot = Join-Path (Join-Path $cacheRoot 'tmp') $runId
$artifactRoot = Join-Path $tmpRoot 'artifacts'
$uiRoot = Join-Path $tmpRoot 'ui\learner'
$logPath = Join-Path $logRoot "$runId.log"
$lectureManifestPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-video.json'
$renderedMediaPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-rendered-media.json'

[void](New-Item -ItemType Directory -Force -Path $logRoot, $artifactRoot, $uiRoot)

$previousTemp = $env:TEMP
$previousTmp = $env:TMP
$previousOutputDir = $env:PLAYWRIGHT_OUTPUT_DIR
$previousSmokeUi = $env:OES_LECTURE_SMOKE_UI
$exitCode = 1
$pushed = $false

try {
    $env:TEMP = $tmpRoot
    $env:TMP = $tmpRoot
    $env:PLAYWRIGHT_OUTPUT_DIR = $artifactRoot

    Push-Location $repo
    $pushed = $true

    "lecture-production-smoke start run=$runId" | Tee-Object -FilePath $logPath -Append

    $renderOutput = & .\scripts\teaching\render-lecture-publish-fixture.ps1 -ManifestPath $lectureManifestPath -RenderedMediaPath $renderedMediaPath 2>&1
    $renderOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Lecture publish fixture render failed with exit code $LASTEXITCODE."
    }

    $publishGateOutput = & .\scripts\teaching\run-lecture-publish-gate.ps1 -ManifestPath $lectureManifestPath -Apply 2>&1
    $publishGateOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Lecture publish gate failed with exit code $LASTEXITCODE."
    }

    $publishGate = ($publishGateOutput | Out-String) | ConvertFrom-Json
    if ($publishGate.publishReady -ne $true) {
        throw 'Lecture publish gate did not return publishReady=true.'
    }

    Get-ChildItem -LiteralPath '.\ui\learner' | Copy-Item -Destination $uiRoot -Recurse -Force
    $resolvedLectureManifestPath = Resolve-LecturePath -Path $lectureManifestPath
    $lecture = Get-Content -LiteralPath $resolvedLectureManifestPath -Raw | ConvertFrom-Json
    $assetRoot = Get-LectureAssetRoot -Lecture $lecture -ManifestPath $resolvedLectureManifestPath
    $publishReadyFullPath = Resolve-LectureContentPath -ContentRoot ([string]$assetRoot.contentRoot) -Path ([string]$publishGate.publishReadyPath)
    $sessionExportOutput = & .\scripts\teaching\export-learner-ui-session.ps1 -OutputPath (Join-Path $uiRoot 'session-data.js') -LecturePackagePath $publishReadyFullPath 2>&1
    $sessionExportOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Learner UI publish session export failed with exit code $LASTEXITCODE."
    }

    if (-not (Test-Path -LiteralPath '.\node_modules\.bin\playwright.ps1' -PathType Leaf)) {
        throw 'Playwright is not installed. Run npm install first.'
    }

    $env:OES_LECTURE_SMOKE_UI = Join-Path $uiRoot 'index.html'
    & .\node_modules\.bin\playwright.ps1 test --config .\playwright.config.js --grep 'selects a rendered lecture package' 2>&1 | Tee-Object -FilePath $logPath -Append
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        [ordered]@{
            schemaVersion = 1
            runId = $runId
            publishReadyPath = $publishGate.publishReadyPath
            uiPath = $env:OES_LECTURE_SMOKE_UI
            logPath = $logPath
            artifactRoot = $artifactRoot
        } | ConvertTo-Json -Depth 6 | Tee-Object -FilePath $logPath -Append
        "lecture-production-smoke passed log=$logPath" | Tee-Object -FilePath $logPath -Append
    }
    else {
        "lecture-production-smoke failed exit=$exitCode log=$logPath artifacts=$artifactRoot" | Tee-Object -FilePath $logPath -Append
    }
}
catch {
    ("lecture-production-smoke error: " + $_.Exception.Message) | Tee-Object -FilePath $logPath -Append
    $exitCode = 1
}
finally {
    if ($pushed) {
        Pop-Location
    }

    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
    $env:PLAYWRIGHT_OUTPUT_DIR = $previousOutputDir
    $env:OES_LECTURE_SMOKE_UI = $previousSmokeUi

    if (-not $KeepArtifacts -and (Test-Path -LiteralPath $tmpRoot)) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force
    }
}

exit $exitCode
