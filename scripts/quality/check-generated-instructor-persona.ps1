[CmdletBinding()]
param(
    [string]$SchemaPath = '.\schemas\generated-instructor-persona.schema.json',
    [string]$DefaultPersonaPath = '.\fixtures\generated-instructor-persona.default.json',
    [string]$PersonaRoot = '.\fixtures\generated-instructor-personas',
    [string]$LectureFixturePath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-video.json',
    [string]$AmericanHistoryPersonaRefPath = '..\open-education-american-history\generated-lectures\amh-reference-intro\persona-reference.json',
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-CheckError {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Message
    )
    $Errors.Add($Message)
}

function Test-HasValue {
    param([object]$Value)

    if ($null -eq $Value) {
        return $false
    }
    if ($Value -is [System.Array]) {
        return @($Value).Count -gt 0
    }
    return -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function Test-HasProperty {
    param(
        [object]$Value,
        [string]$Name
    )

    return $null -ne $Value -and $null -ne $Value.PSObject.Properties[$Name]
}

function Get-PropertyValue {
    param(
        [object]$InputObject,
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing JSON file: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-ExpectedVoiceGender {
    param([string]$InstructorGender)

    switch (($InstructorGender -as [string]).ToLowerInvariant()) {
        'male' { return 'masculine' }
        'female' { return 'feminine' }
        default { return 'neutral' }
    }
}

function Test-ArrayContains {
    param(
        [object]$Values,
        [string]$Expected
    )

    return @($Values | Where-Object { [string]$_ -eq $Expected }).Count -gt 0
}

function Test-RequiredObjectFields {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [object]$Object,
        [string]$Label,
        [string[]]$Fields
    )

    foreach ($field in $Fields) {
        if (-not (Test-HasValue (Get-PropertyValue -InputObject $Object -Name $field))) {
            Add-CheckError $Errors "$Label missing $field."
        }
    }
}

function Test-PersonaContract {
    param(
        [object]$Persona,
        [string]$Label,
        [string[]]$ApprovedConsentValues,
        [bool]$ExpectApproved
    )

    $localErrors = [System.Collections.Generic.List[string]]::new()
    if ($Persona.schemaVersion -ne 1) {
        Add-CheckError $localErrors "$Label schemaVersion must be 1."
    }

    Test-RequiredObjectFields -Errors $localErrors -Object $Persona -Label $Label -Fields @(
        'personaVersion',
        'personaId',
        'status',
        'role',
        'displayName',
        'gender',
        'ageRange',
        'presentationStyle',
        'disclosureLanguage',
        'voiceConsentRule',
        'likenessConsentRule',
        'allowedConsentValues',
        'toneRequirements',
        'prohibitedUses',
        'learnerFacingTransparency',
        'voice',
        'likeness',
        'mannerisms',
        'teachingStyle',
        'operatorReview'
    )

    if ($ExpectApproved -and [string]$Persona.status -ne 'approved') {
        Add-CheckError $localErrors "$Label status must be approved."
    }
    if (-not ([string]$Persona.personaVersion -match '^\d+\.\d+\.\d+$')) {
        Add-CheckError $localErrors "$Label personaVersion must be semver."
    }
    if (-not ([string]$Persona.personaId -match '^oes-[a-z0-9-]+-v\d+$')) {
        Add-CheckError $localErrors "$Label personaId must use oes-...-vN format."
    }

    foreach ($consentValue in @('synthetic-project-owned', 'explicit-consent-recorded')) {
        if (-not (Test-ArrayContains -Values $Persona.allowedConsentValues -Expected $consentValue)) {
            Add-CheckError $localErrors "$Label allowedConsentValues missing $consentValue."
        }
    }

    $voice = Get-PropertyValue -InputObject $Persona -Name 'voice'
    Test-RequiredObjectFields -Errors $localErrors -Object $voice -Label "$Label voice" -Fields @(
        'voiceProfileId',
        'voiceConsent',
        'voiceMatchPolicy',
        'targetInstructorGender',
        'targetVoiceGender',
        'targetVoiceRegister',
        'emotionTargets',
        'providerRefs'
    )

    $likeness = Get-PropertyValue -InputObject $Persona -Name 'likeness'
    Test-RequiredObjectFields -Errors $localErrors -Object $likeness -Label "$Label likeness" -Fields @(
        'likenessProfileId',
        'likenessConsent',
        'realPersonClone',
        'avatarSeedRef',
        'visualStyle',
        'providerRefs'
    )

    $mannerisms = Get-PropertyValue -InputObject $Persona -Name 'mannerisms'
    Test-RequiredObjectFields -Errors $localErrors -Object $mannerisms -Label "$Label mannerisms" -Fields @(
        'gaze',
        'gesture',
        'boardPosture',
        'pace',
        'emotionalRange'
    )

    $teachingStyle = Get-PropertyValue -InputObject $Persona -Name 'teachingStyle'
    Test-RequiredObjectFields -Errors $localErrors -Object $teachingStyle -Label "$Label teachingStyle" -Fields @(
        'toneRequirements',
        'subjectFit',
        'accessibilityDefaults',
        'boardInteractionDefaults'
    )

    $allowed = @($ApprovedConsentValues)
    if ($allowed.Count -eq 0) {
        $allowed = @($Persona.allowedConsentValues)
    }
    foreach ($consentProperty in @(
        @{ Name = 'voice consent'; Value = Get-PropertyValue -InputObject $voice -Name 'voiceConsent' },
        @{ Name = 'likeness consent'; Value = Get-PropertyValue -InputObject $likeness -Name 'likenessConsent' }
    )) {
        if (@($allowed | Where-Object { $_ -eq [string]$consentProperty.Value }).Count -ne 1) {
            Add-CheckError $localErrors "$Label uses unapproved $($consentProperty.Name): $($consentProperty.Value)"
        }
    }

    if ((Get-PropertyValue -InputObject $likeness -Name 'realPersonClone') -ne $false) {
        Add-CheckError $localErrors "$Label likeness must not be a real-person clone."
    }

    if ([string](Get-PropertyValue -InputObject $voice -Name 'voiceMatchPolicy') -ne 'match-generated-instructor-gender') {
        Add-CheckError $localErrors "$Label voiceMatchPolicy must be match-generated-instructor-gender."
    }
    if ([string](Get-PropertyValue -InputObject $voice -Name 'targetInstructorGender') -ne [string]$Persona.gender) {
        Add-CheckError $localErrors "$Label targetInstructorGender must match persona gender."
    }

    $expectedVoiceGender = Get-ExpectedVoiceGender -InstructorGender ([string]$Persona.gender)
    if ([string](Get-PropertyValue -InputObject $voice -Name 'targetVoiceGender') -ne $expectedVoiceGender) {
        Add-CheckError $localErrors "$Label targetVoiceGender must be $expectedVoiceGender for $($Persona.gender) instructors."
    }

    foreach ($tone in @('clear', 'rigorous', 'supportive without false praise', 'specific about evidence')) {
        if (-not (Test-ArrayContains -Values $Persona.toneRequirements -Expected $tone)) {
            Add-CheckError $localErrors "$Label toneRequirements missing $tone."
        }
        if (-not (Test-ArrayContains -Values $teachingStyle.toneRequirements -Expected $tone)) {
            Add-CheckError $localErrors "$Label teachingStyle.toneRequirements missing $tone."
        }
    }

    foreach ($blockedUse in @(
        'real-person voice cloning without explicit consent',
        'real-person likeness cloning without explicit consent',
        'undisclosed generated instruction'
    )) {
        if (-not (Test-ArrayContains -Values $Persona.prohibitedUses -Expected $blockedUse)) {
            Add-CheckError $localErrors "$Label prohibitedUses missing $blockedUse."
        }
    }

    if (-not ([string]$Persona.learnerFacingTransparency).Contains('disclosure')) {
        Add-CheckError $localErrors "$Label learnerFacingTransparency must require disclosure visibility."
    }
    if (@($Persona.operatorReview).Count -lt 4) {
        Add-CheckError $localErrors "$Label operatorReview must include at least four review checks."
    }
    if (@($voice.emotionTargets).Count -lt 2) {
        Add-CheckError $localErrors "$Label voice emotionTargets must include at least two targets."
    }
    if (@($voice.providerRefs).Count -lt 1 -or @($likeness.providerRefs).Count -lt 1) {
        Add-CheckError $localErrors "$Label must include voice and likeness providerRefs."
    }

    return @($localErrors.ToArray())
}

$errors = [System.Collections.Generic.List[string]]::new()

try {
    $schema = Read-JsonFile -Path $SchemaPath
    if ([string]$schema.title -ne 'Open Education Suite Generated Instructor Persona') {
        Add-CheckError $errors 'Generated instructor persona schema title is not stable.'
    }
    foreach ($requiredField in @('schemaVersion', 'personaId', 'status', 'voice', 'likeness', 'mannerisms', 'teachingStyle')) {
        if (-not (Test-ArrayContains -Values $schema.required -Expected $requiredField)) {
            Add-CheckError $errors "Generated instructor persona schema missing required field $requiredField."
        }
    }

    if (-not (Test-Path -LiteralPath $PersonaRoot -PathType Container)) {
        Add-CheckError $errors "Missing persona fixture root: $PersonaRoot"
    }

    $defaultPersona = Read-JsonFile -Path $DefaultPersonaPath
    $approvedConsentValues = @($defaultPersona.allowedConsentValues)
    foreach ($defaultError in @(Test-PersonaContract -Persona $defaultPersona -Label 'default persona' -ApprovedConsentValues $approvedConsentValues -ExpectApproved $true)) {
        Add-CheckError $errors $defaultError
    }

    $approvedPersonas = [System.Collections.Generic.List[object]]::new()
    $approvedPersonas.Add($defaultPersona)
    if (Test-Path -LiteralPath $PersonaRoot -PathType Container) {
        foreach ($fixtureFile in @(Get-ChildItem -LiteralPath $PersonaRoot -Filter '*.json' -File | Sort-Object Name)) {
            $persona = Read-JsonFile -Path $fixtureFile.FullName
            foreach ($personaError in @(Test-PersonaContract -Persona $persona -Label $fixtureFile.Name -ApprovedConsentValues $approvedConsentValues -ExpectApproved $true)) {
                Add-CheckError $errors $personaError
            }
            $approvedPersonas.Add($persona)
        }
    }

    $personaCatalog = @{}
    foreach ($persona in @($approvedPersonas)) {
        $personaId = [string]$persona.personaId
        if ([string]::IsNullOrWhiteSpace($personaId)) {
            continue
        }
        if ($personaCatalog.ContainsKey($personaId)) {
            Add-CheckError $errors "Duplicate approved personaId: $personaId"
        }
        else {
            $personaCatalog[$personaId] = $persona
        }
    }

    $lectureFixtureChecked = $false
    if (Test-Path -LiteralPath $LectureFixturePath -PathType Leaf) {
        $lectureFixtureChecked = $true
        $lecture = Read-JsonFile -Path $LectureFixturePath
        $lecturePersonaId = [string]$lecture.generatedInstructor.personaId
        if (-not $personaCatalog.ContainsKey($lecturePersonaId)) {
            Add-CheckError $errors "Lecture fixture references unapproved personaId: $lecturePersonaId"
        }
        else {
            $approvedPersona = $personaCatalog[$lecturePersonaId]
            if ([string]$lecture.generatedInstructor.disclosure -ne [string]$approvedPersona.disclosureLanguage) {
                Add-CheckError $errors 'Lecture fixture generatedInstructor.disclosure must match approved persona disclosureLanguage.'
            }
            if ([string]$lecture.generatedInstructor.gender -ne [string]$approvedPersona.gender) {
                Add-CheckError $errors 'Lecture fixture generatedInstructor.gender must match approved persona gender.'
            }
            foreach ($consentField in @('voiceConsent', 'likenessConsent')) {
                $consent = [string](Get-PropertyValue -InputObject $lecture.generatedInstructor -Name $consentField)
                if (@($approvedConsentValues | Where-Object { $_ -eq $consent }).Count -ne 1) {
                    Add-CheckError $errors "Lecture fixture generatedInstructor.$consentField is not approved: $consent"
                }
            }
            if ($lecture.generatedInstructor.realPersonClone -ne $false) {
                Add-CheckError $errors 'Lecture fixture generatedInstructor.realPersonClone must be false.'
            }
        }
    }
    else {
        Add-CheckError $errors "Missing lecture fixture for persona contract check: $LectureFixturePath"
    }

    $americanHistoryReferenceChecked = $false
    if (Test-Path -LiteralPath $AmericanHistoryPersonaRefPath -PathType Leaf) {
        $americanHistoryReferenceChecked = $true
        $reference = Read-JsonFile -Path $AmericanHistoryPersonaRefPath
        if ([string]$reference.subjectRepo -ne 'american-history') {
            Add-CheckError $errors 'American History persona reference subjectRepo must be american-history.'
        }
        if ([string]$reference.status -ne 'contract-reference') {
            Add-CheckError $errors 'American History persona reference status must be contract-reference.'
        }
        $referencePersonaId = [string]$reference.personaId
        if (-not $personaCatalog.ContainsKey($referencePersonaId)) {
            Add-CheckError $errors "American History persona reference uses unapproved personaId: $referencePersonaId"
        }
        else {
            $approvedPersona = $personaCatalog[$referencePersonaId]
            if ([string]$reference.disclosureLanguage -ne [string]$approvedPersona.disclosureLanguage) {
                Add-CheckError $errors 'American History persona reference disclosureLanguage must match approved persona disclosureLanguage.'
            }
        }
    }
    else {
        Add-CheckError $errors "Missing American History persona reference: $AmericanHistoryPersonaRefPath"
    }

    $blockedCaseCount = 0
    if ($SelfTest) {
        $blockedRoot = Join-Path $PersonaRoot 'blocked'
        if (-not (Test-Path -LiteralPath $blockedRoot -PathType Container)) {
            Add-CheckError $errors "Missing blocked persona fixture root: $blockedRoot"
        }
        else {
            foreach ($blockedFile in @(Get-ChildItem -LiteralPath $blockedRoot -Filter '*.json' -File | Sort-Object Name)) {
                $blockedCaseCount += 1
                $blockedPersona = Read-JsonFile -Path $blockedFile.FullName
                $blockedErrors = @(Test-PersonaContract -Persona $blockedPersona -Label $blockedFile.Name -ApprovedConsentValues $approvedConsentValues -ExpectApproved $true)
                if ($blockedErrors.Count -eq 0) {
                    Add-CheckError $errors "Blocked persona self-test unexpectedly passed: $($blockedFile.Name)"
                    continue
                }
                $requiredText = [string]$blockedPersona.expectedFailure.requiredErrorContains
                if (-not [string]::IsNullOrWhiteSpace($requiredText)) {
                    $matched = @($blockedErrors | Where-Object { ([string]$_).Contains($requiredText) }).Count -gt 0
                    if (-not $matched) {
                        Add-CheckError $errors "Blocked persona $($blockedFile.Name) did not fail for expected reason: $requiredText"
                    }
                }
            }
        }
        if ($blockedCaseCount -lt 4) {
            Add-CheckError $errors 'Persona contract self-test must include at least four blocked fixtures.'
        }
    }

    $result = [ordered]@{
        schemaVersion = 1
        readOnly = $true
        networkAccess = 'none'
        errorCount = $errors.Count
        approvedPersonaCount = $personaCatalog.Count
        blockedCaseCount = $blockedCaseCount
        lectureFixtureChecked = $lectureFixtureChecked
        americanHistoryReferenceChecked = $americanHistoryReferenceChecked
        errors = @($errors)
    }

    $result | ConvertTo-Json -Depth 12
    if ($errors.Count -ne 0) {
        exit 1
    }
    exit 0
}
catch {
    $errors.Add($_.Exception.Message)
    [ordered]@{
        schemaVersion = 1
        readOnly = $true
        networkAccess = 'none'
        errorCount = $errors.Count
        approvedPersonaCount = 0
        blockedCaseCount = 0
        lectureFixtureChecked = $false
        americanHistoryReferenceChecked = $false
        errors = @($errors)
    } | ConvertTo-Json -Depth 12
    exit 1
}
