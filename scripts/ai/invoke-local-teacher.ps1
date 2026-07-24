[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('ollama', 'lm-studio')]
    [string]$Provider,
    [Parameter(Mandatory)]
    [string]$Model,
    [string]$StatePath = '.\fixtures\learner-state.valid.json',
    [string]$SubjectBrainResultsPath = '',
    [ValidateSet('socratic', 'direct', 'worked-example')]
    [string]$Mode = 'socratic',
    [string]$ApiBase = '',
    [string]$OutputPath = '',
    [string]$PromptPath = '',
    [datetime]$Now = '2026-05-25T12:00:00Z'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (& git -C . rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) {
    throw 'Unable to resolve repository root with git.'
}

if ([string]::IsNullOrWhiteSpace($ApiBase)) {
    $ApiBase = if ($Provider -eq 'ollama') { 'http://127.0.0.1:11434' } else { 'http://127.0.0.1:1234/v1' }
}
$uri = [Uri]$ApiBase
if ($uri.Scheme -ne 'http' -or $uri.Host -notin @('127.0.0.1', 'localhost', '::1')) {
    throw 'Local teacher ApiBase must use HTTP on localhost.'
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Join-Path (Join-Path $repoRoot '.codex-cache') 'tmp') ('local-ai-teacher-response-{0}.json' -f [Guid]::NewGuid().ToString('N'))
}
if ([string]::IsNullOrWhiteSpace($PromptPath)) {
    $PromptPath = Join-Path (Split-Path -Parent $OutputPath) 'local-ai-teacher-prompt.json'
}
foreach ($parent in @((Split-Path -Parent $OutputPath), (Split-Path -Parent $PromptPath))) {
    if (-not [string]::IsNullOrWhiteSpace($parent)) { [void](New-Item -ItemType Directory -Force -Path $parent) }
}

$promptPayload = (& .\scripts\ai\build-teaching-prompt.ps1 -StatePath $StatePath -SubjectBrainResultsPath $SubjectBrainResultsPath -Mode $Mode -Now $Now | Out-String) | ConvertFrom-Json
$promptPayload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $PromptPath
$promptJson = $promptPayload | ConvertTo-Json -Depth 20 -Compress

$systemPrompt = @'
You are an expert adaptive teacher inside Open Education Suite.
Return only one valid JSON object, without Markdown.
Use the desiredOutputShape in the prompt payload.
Use only sourceSnippets.excerpt and subjectBrainContext.results.excerpt for instructional content claims.
Cite exact sourceId, sourceRepo, sourcePath, and locator when available.
Disclose conflicting or insufficient evidence. Preserve the objective and mode.
Separate observed learner evidence from diagnosis. Do not mutate durable learner state.
'@
$messages = @(
    [ordered]@{ role = 'system'; content = $systemPrompt },
    [ordered]@{ role = 'user'; content = "Prompt payload:`n$promptJson" }
)

if ($Provider -eq 'ollama') {
    $body = [ordered]@{
        model = $Model
        messages = $messages
        stream = $false
        format = 'json'
        options = [ordered]@{ temperature = 0.2 }
    } | ConvertTo-Json -Depth 20
    $response = Invoke-RestMethod -Uri ($ApiBase.TrimEnd('/') + '/api/chat') -Method Post -ContentType 'application/json' -Body $body
    $modelContent = [string]$response.message.content
}
else {
    $body = [ordered]@{
        model = $Model
        messages = $messages
        temperature = 0.2
        max_tokens = 1400
        response_format = [ordered]@{ type = 'json_object' }
    } | ConvertTo-Json -Depth 20
    $response = Invoke-RestMethod -Uri ($ApiBase.TrimEnd('/') + '/chat/completions') -Method Post -ContentType 'application/json' -Body $body
    $modelContent = [string]$response.choices[0].message.content
}

$modelOutput = $modelContent | ConvertFrom-Json
$modelOutput | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath
$evaluation = (& .\scripts\ai\evaluate-model-output.ps1 -OutputPath $OutputPath | Out-String) | ConvertFrom-Json
if ($evaluation.errorCount -ne 0) {
    throw 'Local teacher output failed deterministic evaluation.'
}

[ordered]@{
    schemaVersion = 1
    invokedAt = (Get-Date).ToString('o')
    provider = $Provider
    networkScope = 'localhost-only'
    model = $Model
    promptPath = (Resolve-Path -LiteralPath $PromptPath).Path
    outputPath = (Resolve-Path -LiteralPath $OutputPath).Path
    objectiveId = $modelOutput.objectiveId
    citationCount = @($modelOutput.citations).Count
    evaluationErrorCount = $evaluation.errorCount
} | ConvertTo-Json -Depth 8
