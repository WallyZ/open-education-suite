# Subject Repo Course Authoring Template

Use this template inside a subject content repo at:

`study-plans/courses/<COURSE-ID>-<course-slug>.md`

Keep the course original to the subject repo. Link external courseware for reference and inspiration, but do not copy unlicensed videos, transcripts, slides, readings, assignments, tests, or likenesses.

---

## Course Identity

**Course ID:**
**Course title:**
**Subject repo:**
**Level:** introductory | intermediate | advanced | capstone
**Estimated duration:**
**Estimated learner hours:**
**Primary artifact:**
**License for repo-authored material:**
**Last reviewed:**

## Overview

Describe the course in 3 to 6 sentences.

Required:

- What the learner will be able to do by the end.
- Why the course matters in the full program.
- How the course replaces in-class time with video, reading, practice, critique, and assessment.
- What portfolio, project, or mastery evidence the learner will produce.

## Prerequisites

Required prior knowledge:

-

Required tools or accounts:

-

Diagnostic entry checks:

| Check | Evidence | Pass standard | Remediation if not ready |
| --- | --- | --- | --- |
|  |  |  |  |

## Outcomes

Use objective IDs that the adaptive teacher can cite.

| Objective ID | Outcome | Mastery evidence | Misconceptions to watch |
| --- | --- | --- | --- |
| `<subject>:objectives/course/<course-id>/<objective-slug>` |  |  |  |

## Course Structure

| Module or week | Topics | Video seminar | Readings | Practice | Assessment | Deliverable |
| --- | --- | --- | --- | --- | --- | --- |
| Week 1 |  |  |  |  |  |  |

## Videos

Videos replace in-class lecture time. Prefer durable, licensed, or locally generated lecture assets. External videos must stay links unless their license explicitly allows local reuse.

| Video ID | Title | Provider or local asset | URL or path | Duration | Required? | Purpose | License/use boundary | Last reviewed |
| --- | --- | --- | --- | ---: | --- | --- | --- | --- |
|  |  |  |  |  | yes/no |  |  |  |

## Readings

| Reading ID | Title | Provider or local path | Chapter/pages | Required? | Purpose | License/use boundary | Last reviewed |
| --- | --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  | yes/no |  |  |  |

## Practice

Practice should be frequent, specific, and lower stakes than tests or projects.

| Practice ID | Objective IDs | Prompt | Expected evidence | Feedback rule | Estimated time |
| --- | --- | --- | --- | --- | ---: |
|  |  |  |  |  |  |

## Quizzes

| Quiz ID | Objective IDs | Question types | Attempts | Pass standard | Remediation |
| --- | --- | --- | ---: | --- | --- |
|  |  | multiple choice, short answer, trace, critique |  |  |  |

## Tests

Tests should measure transfer, not just recall.

| Test ID | Objective IDs | Format | Time limit | Conditions | Pass standard | Retake policy |
| --- | --- | --- | ---: | --- | --- | --- |
|  |  | written, practical, oral, build test |  |  |  |  |

## Projects

Every course should produce a concrete artifact.

| Project ID | Objective IDs | Brief | Milestones | Required evidence | Submission format |
| --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |

## Rubrics

| Rubric ID | Applies to | Criteria | Meets standard | Exceeds standard | Revision guidance |
| --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |

## Support

Learner supports:

- Setup help:
- Worked examples:
- Office-hours equivalent:
- Peer/community option:
- Accessibility supports:
- Common blocker playbook:

## Policies

Required policies:

- Academic honesty:
- AI/tool use:
- Collaboration:
- Late or revision work:
- Accessibility/accommodation:
- External content licensing:
- Generated media disclosure:

## Adaptive Hooks

Define how the teacher adapts while still covering the required material.

| Hook ID | Trigger evidence | Teacher response | Material still covered | Practice opportunity | Review timing |
| --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |

## Remediation Map

| Misconception or gap | Detection signal | Corrective explanation | Practice item | Recheck |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |

## Accessibility

Required:

- Captions or transcript for required video.
- Alt text for images, slides, and diagrams.
- Keyboard-accessible interactive materials.
- Text alternatives for audio-only or video-only information.
- Clear time estimates and workload expectations.

## External Source Links

Use this section for MIT OCW, Open Learning Library, CS50, Stanford SEE, CMU OLI, OpenStax, OpenLearn, Saylor, Nand2Tetris, university pages, books, talks, or documentation used as references.

| Provider | Title | URL | Source type | Borrowed pattern | License/use boundary | Last reviewed | Broken link status |
| --- | --- | --- | --- | --- | --- | --- | --- |
|  |  |  | course, textbook, lecture, assignment, project, documentation |  | link-only, reusable with attribution, original rewrite required | YYYY-MM-DD | unknown |

## Course Design Review

Before marking this course ready, every item should be true or have an explicit gap note.

| Requirement | Status | Evidence or gap |
| --- | --- | --- |
| Overview present | todo |  |
| Prerequisites present | todo |  |
| Outcomes/objective IDs present | todo |  |
| Module/week map present | todo |  |
| Video seminar substitutes present | todo |  |
| Readings present | todo |  |
| Practice present | todo |  |
| Quizzes present | todo |  |
| Tests present | todo |  |
| Projects present | todo |  |
| Rubrics present | todo |  |
| Support plan present | todo |  |
| Policies present | todo |  |
| Adaptive hooks present | todo |  |
| Accessibility notes present | todo |  |
| External source links reviewed | todo |  |

## Package Metadata Block

Copy this block into the course object metadata when the subject repo format supports structured metadata.

```json
{
  "courseStructure": {
    "level": "",
    "estimatedHours": 0,
    "moduleCount": 0,
    "primaryArtifact": ""
  },
  "courseDesignReview": {
    "overviewPresent": false,
    "prerequisitesPresent": false,
    "outcomesPresent": false,
    "moduleMapPresent": false,
    "videosPresent": false,
    "readingsPresent": false,
    "practicePresent": false,
    "quizzesPresent": false,
    "testsPresent": false,
    "projectsPresent": false,
    "rubricsPresent": false,
    "supportPresent": false,
    "policiesPresent": false,
    "adaptiveHooksPresent": false,
    "accessibilityNotesPresent": false
  },
  "externalSourceLinks": [
    {
      "provider": "",
      "title": "",
      "url": "",
      "sourceType": "",
      "borrowedPattern": "",
      "licenseUseBoundary": "",
      "lastReviewed": "YYYY-MM-DD",
      "brokenLinkStatus": "unknown"
    }
  ]
}
```
