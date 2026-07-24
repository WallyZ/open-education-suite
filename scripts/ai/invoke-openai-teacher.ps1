[CmdletBinding()]
param(
    [string]$StatePath = '.\fixtures\learner-state.valid.json',
    [string]$SubjectBrainResultsPath = '',
    [ValidateSet('socratic', 'direct', 'worked-example')]
    [string]$Mode = 'socratic',
    [string]$Model = '',
    [string]$OutputPath = '',
    [string]$PromptPath = '',
    [datetime]$Now = '2026-05-25T12:00:00Z'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    $repo = (& git -C . rev-parse --show-toplevel).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repo)) {
        throw 'Unable to resolve repository root with git.'
    }
    return $repo
}

$apiKey = $env:OPENAI_API_KEY
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    throw 'OPENAI_API_KEY is required for live teacher invocation.'
}

if ([string]::IsNullOrWhiteSpace($Model)) {
    $Model = if ([string]::IsNullOrWhiteSpace($env:OPENAI_MODEL)) { 'gpt-4.1-mini' } else { $env:OPENAI_MODEL }
}

$baseUrl = if ([string]::IsNullOrWhiteSpace($env:OPENAI_BASE_URL)) { 'https://api.openai.com' } else { $env:OPENAI_BASE_URL.TrimEnd('/') }
$repoRoot = Resolve-RepoRoot

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Join-Path (Join-Path $repoRoot '.codex-cache') 'tmp') ('live-ai-teacher-response-{0}.json' -f [Guid]::NewGuid().ToString('N'))
}
if ([string]::IsNullOrWhiteSpace($PromptPath)) {
    $PromptPath = Join-Path (Split-Path -Parent $OutputPath) 'live-ai-teacher-prompt.json'
}

$outputParent = Split-Path -Parent $OutputPath
$promptParent = Split-Path -Parent $PromptPath
if (-not [string]::IsNullOrWhiteSpace($outputParent)) {
    [void](New-Item -ItemType Directory -Force -Path $outputParent)
}
if (-not [string]::IsNullOrWhiteSpace($promptParent)) {
    [void](New-Item -ItemType Directory -Force -Path $promptParent)
}

$promptPayload = (& .\scripts\ai\build-teaching-prompt.ps1 -StatePath $StatePath -SubjectBrainResultsPath $SubjectBrainResultsPath -Mode $Mode -Now $Now | Out-String) | ConvertFrom-Json
$promptPayload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $PromptPath
$promptJson = $promptPayload | ConvertTo-Json -Depth 20 -Compress

$systemPrompt = @'
You are an expert adaptive teacher inside Open Education Suite.

Return only one valid JSON object. Do not wrap it in Markdown.

The JSON object must use this shape:
{
  "schemaVersion": 1,
  "objectiveId": "...",
  "mode": "socratic|direct|worked-example",
  "response": "learner-facing text",
  "citations": [{ "sourceId": "...", "sourceRepo": "...", "sourcePath": "...", "claim": "..." }],
  "observedEvidence": ["..."],
  "diagnosis": { "type": "...", "confidence": 0.0, "rationale": "..." },
  "nextStep": { "type": "question|practice|review|project", "text": "..." },
  "stateUpdateProposal": { "type": "none|proposal", "reason": "..." },
  "selfCheck": {
    "grounded": true,
    "objectiveAligned": true,
    "accessible": true,
    "tone": "rigorous-supportive",
    "unsupportedClaims": [],
    "directStateMutation": false
  }
}

Use only sourceSnippets.excerpt and subjectBrainContext.results.excerpt for instructional content claims.
Include at least one citation using the exact sourceId, sourceRepo, and sourcePath from the source snippet you used.
When subject-brain context is used, preserve its locator and disclose conflicting or insufficient evidence.
Preserve the provided objectiveId and mode.
Separate observed evidence from diagnosis.
In Socratic mode, ask a calibrated question before revealing an answer.
Preserve learner preferences and accommodations in the response style and mention them in observedEvidence when present.
Do not directly mutate learner state.
'@

$requestBody = [ordered]@{
    model = $Model
    messages = @(
        [ordered]@{
            role = 'system'
            content = $systemPrompt
        },
        [ordered]@{
            role = 'user'
            content = "Prompt payload:`n$promptJson"
        }
    )
    temperature = 0.2
    max_tokens = 1400
    response_format = [ordered]@{
        type = 'json_object'
    }
} | ConvertTo-Json -Depth 20

$headers = @{
    Authorization = "Bearer $apiKey"
}

$apiResponse = Invoke-RestMethod -Uri "$baseUrl/v1/chat/completions" -Method Post -Headers $headers -ContentType 'application/json' -Body $requestBody
$modelContent = [string]$apiResponse.choices[0].message.content
$modelOutput = $modelContent | ConvertFrom-Json
$modelOutput | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath

[ordered]@{
    schemaVersion = 1
    invokedAt = (Get-Date).ToString('o')
    provider = 'openai'
    model = $Model
    promptPath = (Resolve-Path -LiteralPath $PromptPath).Path
    outputPath = (Resolve-Path -LiteralPath $OutputPath).Path
    objectiveId = $modelOutput.objectiveId
    citationCount = @($modelOutput.citations).Count
} | ConvertTo-Json -Depth 8
