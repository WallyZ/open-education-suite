# System Patterns

## Boundaries

- Core platform repo: ingestion, state, assessment, orchestration, UI, QA contracts.
- Subject content repos: study plans, resources, generated lectures, subject manifests.
- QA Live repo: harness implementation and host automation.
- 00-repo-kit: shared process/tooling standards.

## Key patterns

- `content-sources.json` declares sibling content repos and manifests.
- Ingestion scripts read content repos and build local packages without mutating sources.
- Learner state updates are deterministic and audited.
- AI teacher output is evaluated for groundedness and cannot directly mutate state.
- QA Live specs live in `qa-live/`; runner scripts call the adjacent QA system.
- TODO lifecycle checks run through the canonical verifier.
