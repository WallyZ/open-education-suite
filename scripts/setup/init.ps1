# ---------------------------------------------
# Open Education Suite - Repository Scaffolding
# PowerShell 7 Script
# ---------------------------------------------

$root = "open-education-suite"

# Create root directory
New-Item -ItemType Directory -Path $root -Force | Out-Null

# Helper function to create folders
function Make-Folder {
    param([string]$path)
    New-Item -ItemType Directory -Path $path -Force | Out-Null
}

# Helper function to create files with optional content
function Make-File {
    param(
        [string]$path,
        [string]$content = ""
    )
    New-Item -ItemType File -Path $path -Force | Out-Null
    if ($content -ne "") {
        Set-Content -Path $path -Value $content
    }
}

# -----------------------------
# Root-level files
# -----------------------------
Make-File "$root/README.md"
Make-File "$root/WORKFLOW.md"
Make-File "$root/USAGE.md"

# -----------------------------
# Tools directory
# -----------------------------
$tools = "$root/tools"
Make-Folder $tools

$toolSubDirs = @(
    "pdf-to-anki",
    "summarizers",
    "quiz-generators",
    "resource-scrapers"
)

foreach ($dir in $toolSubDirs) {
    Make-Folder "$tools/$dir"
    Make-File "$tools/$dir/README.md"
}

# -----------------------------
# Study Plans directory
# -----------------------------
$studyPlans = "$root/study-plans"
Make-Folder $studyPlans

$studyPlanSubDirs = @(
    "templates",
    "software-development",
    "cybersecurity",
    "data-science",
    "examples"
)

foreach ($dir in $studyPlanSubDirs) {
    Make-Folder "$studyPlans/$dir"
}

# Template file
Make-File "$studyPlans/templates/study-plan-template.md"

# -----------------------------
# Resources directory
# -----------------------------
$resources = "$root/resources"
Make-Folder $resources

$resourceSubDirs = @(
    "textbooks",
    "courses",
    "youtube",
    "practice-sites",
    "curated-lists"
)

foreach ($dir in $resourceSubDirs) {
    Make-Folder "$resources/$dir"
}

# -----------------------------
# Docs directory
# -----------------------------
$docs = "$root/docs"
Make-Folder $docs

$docFiles = @(
    "architecture-overview.md",
    "contribution-guide.md",
    "roadmap.md"
)

foreach ($file in $docFiles) {
    Make-File "$docs/$file"
}

# -----------------------------
# Scripts directory
# -----------------------------
$scripts = "$root/scripts"
Make-Folder $scripts

$scriptSubDirs = @(
    "setup",
    "ingestion",
    "automation"
)

foreach ($dir in $scriptSubDirs) {
    Make-Folder "$scripts/$dir"
}

Write-Host "Scaffolding complete for 'open-education-suite'." -ForegroundColor Green
