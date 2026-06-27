# TODO 21: Generated Instructor Persona Contract

Goal: stabilize the reusable generated-instructor contract so the suite can safely select teacher personas, subject repos can reference them, and a future `open-education-teacher` repo can own reusable persona assets without mixing them into course content.

## Work Items

- [x] Add a versioned `schemas/generated-instructor-persona.schema.json` contract covering identity, disclosure, consent, gender/voice matching, likeness safety, mannerisms, teaching style, and operator review. <!-- ms:evidence id=21-persona-schema path=schemas/generated-instructor-persona.schema.json strings=personaVersion,voiceMatchPolicy,operatorReview -->
- [x] Promote the default generated instructor fixture into the stable contract while preserving the legacy fields used by existing lecture-video checks. <!-- ms:evidence id=21-default-persona path=fixtures/generated-instructor-persona.default.json strings=teacherRepoReadiness,realistic-synthetic-instructor-at-chalkboard,match-generated-instructor-gender -->
- [x] Add approved male, female, and neutral persona fixtures with voice register, emotion targets, board mannerisms, and consent-safe likeness metadata. <!-- ms:evidence id=21-approved-fixtures path=fixtures/generated-instructor-personas/approved-male-calm-professor.json;fixtures/generated-instructor-personas/approved-female-energetic-professor.json;fixtures/generated-instructor-personas/approved-neutral-clear-coach.json strings=targetVoiceGender,realPersonClone,boardPosture -->
- [x] Add blocked fixtures for real-person cloning, missing disclosure, unapproved consent, and voice/gender mismatch so the contract checker proves negative cases fail. <!-- ms:evidence id=21-blocked-fixtures path=fixtures/generated-instructor-personas/blocked/blocked-real-person-clone.json;fixtures/generated-instructor-personas/blocked/blocked-missing-disclosure.json;fixtures/generated-instructor-personas/blocked/blocked-unapproved-consent.json;fixtures/generated-instructor-personas/blocked/blocked-voice-gender-mismatch.json strings=expectedFailure,real-person clone,targetVoiceGender -->
- [x] Add `scripts/quality/check-generated-instructor-persona.ps1` and wire it into `scripts/codex-verify.ps1` with `-SelfTest` enabled. <!-- ms:evidence id=21-persona-checker path=scripts/quality/check-generated-instructor-persona.ps1;scripts/codex-verify.ps1 symbols=check-generated-instructor-persona.ps1 strings=SelfTest,approvedPersonaCount,blockedCaseCount -->
- [x] Add pilot references proving the contract works for both the existing GDEV lecture object and the American History pilot repo without copying subject media into the suite. <!-- ms:evidence id=21-pilot-refs path=../open-education-game-development/generated-lectures/gdev-101-design-vocabulary/lecture-video.json;../open-education-american-history/generated-lectures/amh-reference-intro/persona-reference.json strings=oes-default-generated-instructor-v1,contract-reference -->
- [x] Document the stabilization criteria and future `open-education-teacher` split boundary in the generated lecture video guidance. <!-- ms:evidence id=21-docs path=docs/generated-lecture-video.md strings=Persona Contract Stabilization,open-education-teacher,blocked fixtures -->

## Acceptance Notes

- The suite owns the schema, selector contract, disclosure/consent policy, and verifier gate.
- A future `open-education-teacher` repo should own reusable voice profiles, avatar seeds, mannerism profiles, approved samples, and provider routing metadata after this contract remains stable.
- Subject repos own finished lecture packages, transcripts, captions, board visuals, checksums, and subject-specific persona references.
