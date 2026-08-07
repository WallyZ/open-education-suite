# Community Commons Learning Integration

Status: proposed platform contract; no runtime adapter exists

## Purpose

Open Education Suite is the learning authority for the planned Community
Commons / Skill Forge product. It receives bounded learning events from an
immersive session without becoming the session server, organization database,
game backend, or repository for raw recordings.

The first proof is an adult bicycle flat-repair lesson inside one Chapter Hall.
The Suite must remain content-agnostic: activity content, instructor media, and
immersive object definitions belong to the future Community Commons product or
an approved subject/content repo.

## Authority Boundary

Open Education Suite owns:

- learner-controlled identity mapping;
- lesson and objective references;
- attempts, feedback, hint use, assessment, mastery, and review scheduling;
- transfer-check and teach-back evidence summaries;
- credential rules and explicit non-credential claims;
- correction, export, revocation, and deletion of learning records.

Open Education Suite does not own:

- Community Core membership, chapter, event, consent, service, or governance;
- Community Commons presence, voice, object state, moderation, or raw telemetry;
- Infinite Worlds game state, NPC state, crafting, settlement, or progression;
- raw voice, motion, gaze, face, biometric, transcript, or private conversation;
- source lesson media or creator-production files.

## First Learning Modes

The bicycle repair exemplar must distinguish:

1. demonstration;
2. guided practice;
3. independent practice;
4. diagnosis of a fault or failed repair;
5. teach-back to another participant or simulated learner;
6. real-world checkoff handoff.

Simulation completion is not proof of real-world competence and cannot become
a professional qualification. Transfer evidence and any qualified real-world
checkoff must be stored as separate claims with their own authority.

## Minimal Learning Event

The first versioned event should contain only what the learning decision needs:

- pseudonymous learner reference scoped to the integration;
- activity, objective, mode, activity-pack revision, and rubric revision;
- attempt identifier, sequence, declared support level, and outcome;
- bounded error and feedback codes, not a raw behavioral stream;
- learner-visible evidence references that do not expose machine paths;
- consent receipt reference, event time, producer, schema version, and replay
  protection;
- source-session correlation token with a short retention window.

Raw pose samples, hand paths, voice, video, transcripts, eye tracking, exact
room movement, private messages, unrelated participant data, and full session
logs are forbidden. If richer evidence is scientifically necessary, it needs a
separate approved research contract and cannot be added to the production event
by convenience.

## Processing And Failure Rules

- Validate schema, producer, audience, expiry, consent, and replay status before
  changing learner state.
- Preserve idempotency across reconnect and retry.
- Keep the immersive activity usable in a safe degraded mode if the Suite is
  unavailable; queue only the minimal encrypted event when consent allows.
- Never fabricate mastery because a session completed or a service timed out.
- Return only a learner-approved coarse claim to Community Core.
- Support correction, export, revocation, deletion, and backup-deletion
  acknowledgement.
- Record the exact activity, rubric, event, adapter, and Suite revisions used
  for every decision.

## Pedagogy And Quality

The first lesson needs explicit objectives, prerequisites, hazards, common
errors, alternative valid methods, prompt-fading rules, retry behavior,
teach-back criteria, transfer criteria, and an independent expert review.

Evaluation must distinguish:

- following a prompt from recalling a sequence;
- manipulating a simulated object from diagnosing a real fault;
- completing one variant from transferring across bicycle and equipment
  variants;
- performing a task from teaching it safely;
- in-simulation evidence from real-world checkoff.

The planned adapter should consult the reusable pedagogy and safety contracts
owned by `open-education-teacher` without moving learner state or runtime/UI into
that repo.

## Safeguarding And Privacy

The first proof is adult-only. Youth participation remains a separately
governed future program. The learning adapter must not create or normalize
hidden adult-minor contact, and it must not infer legal age from a lesson event.

Any future youth design needs independently reviewed age assurance, guardian
authority, staff clearance, room visibility, communication, escalation,
retention, investigation, and appeals. Community Core and Community Commons own
their respective organizational and session enforcement; the Suite owns safe
learning-data behavior.

## Acceptance Evidence

Before a closed adult pilot:

- valid and invalid schema fixtures pass;
- expiry, replay, duplicate, forged, consent-revoked, correction, and deletion
  cases pass;
- service outage, retry, reconnect, and conflicting attempt order pass;
- the full demonstration-to-transfer journey is QA Live testable;
- data inspection proves forbidden raw data is absent;
- accessibility and learner agency are reviewed;
- an independent critic inspects raw evidence;
- the owner approves the exact adapter and pilot revisions.

Open implementation work is tracked in
`docs/todo/TODO_05_interoperability_quality_and_research.md`.
