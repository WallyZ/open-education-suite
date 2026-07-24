# Subject Brain Federation

## Purpose

Open Education Suite separates a teacher's knowledge, pedagogy, curriculum,
and learner evidence instead of treating one language model as all four.

| Layer | Owner | Question answered |
| --- | --- | --- |
| Daily curriculum and source seed | Subject content repo | What must this learner study and demonstrate today? |
| Specialist subject brain | Subject-brain repo | What licensed evidence, definitions, examples, and disagreements bear on the question? |
| Teacher profile | `open-education-teacher` | How should the material be explained, questioned, modeled, and practiced? |
| Orchestration and learner state | `open-education-suite` | What context is allowed, what comes next, and which checked update may be applied? |

The course seed remains the authority for the scheduled lesson. A specialist
brain supplements it; it does not silently replace the course objective,
assessment, source boundaries, or teacher-reviewed answer key.

## Discovery

`subject-brains.json` is the suite-owned registry. Active entries resolve to a
repo-owned `subject-brain.json`. All thirteen K-12 contracts now resolve
locally: three have checked starter corpora and ten are contract-ready only.
Contract-ready entries expose rights, evidence, and acquisition boundaries
without pretending that a usable service or corpus already exists.

Every active brain provides:

- a subject and grade-band manifest;
- a rights-gated corpus manifest with canonical and alternate source routes;
- an evidence policy and corpus plan;
- deterministic checksums for local files;
- retrieval-only cited context; and
- explicit safety and state-mutation boundaries.

## Local Workflow

Validate all registered active brains:

```powershell
.\scripts\ai\subject-brain.ps1 -Action validate-registry
```

Recreate the ten missing-repo contract scaffolds only in a workspace where
those target directories do not already exist:

```powershell
.\scripts\setup\build-planned-subject-brains.ps1
```

The generator refuses to overwrite an existing directory.

Build a local lexical index for one brain:

```powershell
.\scripts\ai\subject-brain.ps1 -Action index `
  -BrainRoot ..\critical-thinking-ai-tool `
  -IndexPath .\.codex-cache\tmp\critical-thinking.sqlite
```

Retrieve teacher context:

```powershell
.\scripts\ai\subject-brain.ps1 -Action query `
  -IndexPath .\.codex-cache\tmp\critical-thinking.sqlite `
  -Question 'What makes a deductive argument valid?' `
  -GradeBand 9-12
```

The result contains excerpts and source locators, not a generated answer. Pass
the saved result to `build-teaching-prompt.ps1 -SubjectBrainResultsPath ...`.
The teacher model must cite each used excerpt and state when evidence is
missing or conflicting.

## Ingestion Boundary

Only a corpus item with all of the following is indexed:

1. a repo-relative local path;
2. a matching SHA-256 checksum;
3. `rightsStatus: approved-for-local-index`; and
4. `acquisition.status: local-ready`.

Link-only, purchased, unclear, noncommercial-only, and permission-required
items remain discoverable metadata but are not indexed. Private learner work,
credentials, embeddings from private notes, and chat transcripts never belong
in a public corpus manifest.

The stdlib runtime handles text, Markdown, HTML, JSON, CSV, DOCX, and EPUB.
PDF extraction uses PyPDF or PyMuPDF when one is already available and reports
an explicit skip otherwise. No verifier installs dependencies or uses network.

## Supporting Repositories

- `source-preservation-kit` supplies durable capture/provenance contracts.
- `ebook_organizer` can inventory and classify owner-held ebooks before rights review.
- `VideoDL` can prepare owner-approved transcripts from licensed media.
- `open-web-search-local` supplies discovery, not durable curricular authority.
- `news-intel-bot` supplies time-sensitive leads that require preservation and review.
- `assessment-mastery-engine` evaluates evidence; it is not a content authority.
- `content-courseware-kit` packages course metadata; it does not own subject facts.

The legacy `chatgpt-retrieval-plugin` and `ue_docs_rag` are reference
implementations, not default K-12 providers. The former is cloud-oriented and
the latter is a narrow Unreal Engine corpus without this rights and pedagogy
contract.

## Readiness Levels

- `contract-ready`: manifest and policy validate, but no usable local corpus is guaranteed.
- `starter-corpus-ready`: at least one rights-approved source can be queried locally.
- `pilot-ready`: grade-banded gold questions, citation checks, safety tests, and teacher transcript review pass.
- `production-ready`: coverage, freshness, accessibility, conflict handling, and qualified external review are evidenced.

Three initial brains are `starter-corpus-ready`; the remaining ten are
`contract-ready`. No brain is claimed above starter-corpus readiness.
