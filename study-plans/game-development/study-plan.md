# Solo Unreal (VR-ready) Game Development — Study Plan

A comprehensive, **solo-developer** learning path for taking a game from idea → playable prototype → vertical slice → production-ready release foundation.

This plan is written to match the structure of the Open Education Suite templates you already have, while expanding it into a full “university-style” curriculum map with practical milestones.

---

## 1. Overview

**Goal:** Build the core competency stack needed to ship a commercial-quality Unreal Engine game solo (with VR support as a first-class constraint), while creating a portfolio of shippable prototypes and one strong vertical slice.

**Why this matters:** Most solo dev failures are not due to one missing skill, but to *gaps between skills* (e.g., you can code, but can’t scope; you can make art, but can’t optimize; you can build a prototype, but can’t market it). This plan is designed around those “handoff gaps.”

**Target timeline options:**
- **Track A (10–12 hrs/week):** ~12 months to a strong vertical slice + production foundation.
- **Track B (20–25 hrs/week):** ~6–8 months to the same outcomes.
- **Track C (30+ hrs/week):** ~4–6 months (higher burnout risk; requires stricter scoping).

**Primary engine:** Unreal Engine (Blueprints + C++ hybrid).  
Epic’s guidance on balancing Blueprints and C++ and the official UE learning paths are used throughout. (See citations in the Resources section.) 

---

## 2. Resources

### Primary Resources (Curriculum anchors)

These references are used to validate what you study against real degree programs and industry expectations:

- **DigiPen — CS + Game Design degree requirements & sample course sequence** (computer science + math/physics + game projects).  
- **RIT — Game Design & Development** (degree expectations and flowchart).  
- **University of Utah — Entertainment Arts & Engineering (EAE)** (tracks that mirror real team disciplines).  
- **USC Interactive Media & Games** (interactive media foundations and game-focused curriculum).  
- **SMU Guildhall** (art/design/production/programming cornerstones).

(These are cited inline in later sections.) 

### Unreal Engine official learning & documentation
- Epic Developer Community learning path: **Welcome to Game Development**.  
- **Best Practices for Blueprints and C++**, plus **Converting Blueprint to C++**.  
- **OpenXR Input in Unreal** (VR input architecture).  
- **VR Performance Testing in Unreal** and related profiling/performance guidance.

### Generative visuals (LLM / diffusion / video)
- Stability AI’s **Stable Diffusion 3.5 Prompt Guide** (prompt structure and refinement).  
- ComfyUI documentation for **Conditioning** and related prompt-conditioning tools.  
- Runway’s official **Gen-3 prompting guide** (if you use cloud video generation).  
- Stability AI’s **Stable Video Diffusion** resources and research pages (if you explore local/open models).

### PR & marketing (shipping reality)
- Steamworks docs: **store graphical assets** and **store page editing** (production constraints you must design for early).  
- **presskit()** (industry-standard press kit structure).  
- Indie marketing strategy references (e.g., wishlist and store-page timing guidance).

---

## 3. Topic Breakdown (University-style competency map)

> Use this table as the “degree plan.” Each topic includes *what mastery looks like* and a practical output you can ship or demonstrate.

| Domain | What you must be able to do | Mastery checkpoint (deliverable) |
|---|---|---|
| A. Game Ideation & Synthesis | Turn raw ideas into a coherent, testable concept with an audience fit | 1-page game pitch + “pillars” + competitor scan + risk list |
| B. Game Design Documentation | Produce clear design docs that survive iteration (systems + UX + content) | GDD v1 + living changelog + playtest notes loop |
| C. Planning & Production | Scope, schedule, and de-risk like a producer (even solo) | Backlog + sprint cadence + risk burndown + definition of done |
| D. Unreal Fundamentals | Navigate UE editor, content, assets, build targets | 3 micro-prototypes shipped (packaged builds) |
| E. Blueprint Prototyping | Rapid iteration, debugging, data-driven design | Prototype “mechanic kit” in BP (modular, reusable) |
| F. Unreal C++ | Gameplay framework, modules, performance-minded code | Convert a BP system to C++ cleanly (with tests where possible) |
| G. Gameplay Systems | Input → state → feedback loops, combat, interaction, inventory, AI | Vertical-slice core loop + telemetry logging |
| H. VR Interaction & UI/UX | Comfortable interaction, locomotion, UI in 3D space | VR interaction sandbox + usability playtest report |
| I. Art & Content Pipeline | Blockout → modeling → UV → materials → animation → optimization | 1 environment kit + 1 character/creature + LODs + budgets met |
| J. Lighting & Rendering | Pick appropriate lighting pipeline, optimize for target hardware | Performance budget met in worst-case scene |
| K. Audio | SFX pipeline, spatial audio, mix basics | Audio pass for the vertical slice + loudness checks |
| L. QA & Build/Release | Bug triage, automated checks, packaging, crash reproduction | Release candidate checklist + reproducible build |
| M. PR & Marketing | Store page assets, messaging, press kit, devlog cadence | Steam page-ready asset pack + press kit + trailer script |

---

## 4. Detailed Roadmap (12-month / 48-week plan)

### Phase 0 — Setup & Foundations (Week 0–1)
**Outcomes**
- Unreal + IDE toolchain installed and validated.
- Repo structure for game + docs + builds + “evidence” logs.

**Tasks**
- Install UE, Visual Studio toolchain, source control (Git + LFS recommended for solo).
- Create a “Learning Journal” folder with weekly notes and build links.
- Create a “Prototype Vault” folder: every prototype must produce a packaged build.

---

### Phase 1 — Core Game Dev Foundations via Micro-Prototypes (Weeks 2–8)
**Purpose:** Learn *by shipping small things.*  
**Micro-prototypes (ship 3):**
1) **Physics toy** (grab/throw/impact feedback)  
2) **Melee combat toy** (hit detection + stamina + reactions)  
3) **Traversal toy** (movement, climbing/interaction, VR-safe options)

**Weekly cadence**
- 1 day learning (engine/system)
- 2–3 days building
- 1 day playtest + notes + refactor
- 1 day polish + packaging

**Key skills**
- Blueprints, actor components, data tables, debugging, profiling basics.

---

### Phase 2 — GDD + Systems Thinking + De-risking (Weeks 9–14)
**Purpose:** Lock the *shape* of the game before scaling content.

**Deliverables**
- **Game Pitch** (1 page): audience, hooks, pillars, differentiators.
- **GDD v1**: core loop, progression, content rules, UX flows.
- **Risk Register**: tech risks (VR perf, interaction), content risks, production risks.

**Practice**
- “Design by test”: every pillar must map to at least one measurable playtest question.

---

### Phase 3 — Unreal C++ + Architecture (Weeks 15–22)
**Purpose:** Build the spine of a game that won’t collapse under content.

**Focus**
- Gameplay framework (GameMode/GameState/PlayerController/Character).
- Components, interfaces, data-driven design.
- Converting a BP system to C++ safely.

**Deliverables**
- A modular **interaction system** (interface-driven).
- A **combat component** (damage, reactions, stamina, timing windows).
- A reusable **save/load** stub (even if minimal).

---

### Phase 4 — Content Pipeline + Visual Production (Weeks 23–32)
**Purpose:** Learn the art pipeline and hit performance budgets early.

**Content targets**
- One environment kit (modular pieces).
- One “hero prop set” (interactive objects).
- One character or creature (even if simple).

**Generative visuals workflow (recommended)**
- Use AI for *concept exploration* and moodboards.
- Convert approved concepts into game-ready assets (retopo/UV/LOD/optimization).
- Maintain a style bible (prompts, palettes, shape language, materials).

**Deliverables**
- Style guide + prompt library.
- Asset budget sheet (tris/material count/texture sizes).
- Worst-case scene performance test.

---

### Phase 5 — VR Interaction + UI + Comfort (Weeks 33–40)
**Purpose:** Make interaction *feel inevitable* and comfortable.

**Key systems**
- Interaction primitives: grab, pull, push, throw, lever, button.
- Diegetic UI patterns (wrist UI, world panels, physical inventory).
- Comfort options: snap turn, vignetting, teleport vs smooth locomotion.

**Deliverables**
- VR interaction sandbox (test room).
- UI pass (menus + in-world UI).
- Usability playtest notes from at least 5 sessions.

---

### Phase 6 — Production Readiness + PR/Marketing Foundation (Weeks 41–48)
**Purpose:** Make the project “real” to players and to your future self.

**Production readiness**
- Build pipeline, crash repro, logging.
- Settings menu, accessibility pass (baseline).
- Demo/vertical slice packaging plan.

**Marketing outputs**
- Store-page-ready screenshots (true in-engine).
- Capsule/key art draft set.
- Short trailer script + shot list.
- Press kit page.

---

## 5. Weekly Schedule (Example: first 12 weeks)

> Adjust the hours per week, but keep the *pattern* consistent.

- **Week 1:** Install & validate toolchain; ship “Hello Unreal” packaged build.
- **Week 2:** Blueprint basics → Prototype #1 (physics toy) playable.
- **Week 3:** Feedback polish + profiling basics → Prototype #1 packaged.
- **Week 4:** Prototype #2 (melee toy) core loop.
- **Week 5:** Prototype #2 polish + modularize combat component.
- **Week 6:** Prototype #3 (traversal toy) + VR comfort baseline.
- **Week 7:** Consolidate: build an “interaction kit” shared across prototypes.
- **Week 8:** Portfolio polish: packaged builds + short writeups + video captures.
- **Week 9:** Write game pitch; define pillars and “non-goals”.
- **Week 10:** Draft GDD v1; map each pillar to gameplay tests.
- **Week 11:** Build vertical-slice plan: feature list + scope cuts + risks.
- **Week 12:** Prototype a “vertical slice skeleton” (menu → play → end → menu).

---

## 6. Flashcard Integration (spaced repetition)

Use your PDF → Anki pipeline for:
- Unreal architecture terms (framework classes, lifecycle, replication basics).
- C++ patterns you use repeatedly (RAII, pointers/references, containers).
- Math/physics essentials (vectors, quaternions, dot/cross, spring forces).
- VR UX heuristics and comfort constraints.
- Marketing vocabulary (capsules, wishlists, conversion, demo beats).

Suggested default:
- **Deck:** “Unreal Solo Dev”
- **Daily reviews:** 20–40 cards/day
- **Mastery threshold:** 90% mature cards correct

---

## 7. Practice & Projects (what you build)

### Mini-projects (non-negotiable)
1) **Interaction sandbox** (VR-friendly)  
2) **Combat sandbox** (stamina + hit reactions + readable feedback)  
3) **Vertical slice** (one short “mission” or “scenario” with start→end)

### Capstone (end of Year 1)
A polished vertical slice that proves:
- The core loop is fun.
- The interaction system scales.
- Performance is viable for your target hardware.
- Your store-page messaging matches what players actually do in-game.

---

## 8. Progress Tracking (simple + strict)

Track weekly:
- **Build shipped?** (packaged build link + notes)
- **What improved?** (1–3 bullet “wins”)
- **What hurt?** (1–3 bullet “frictions”)
- **Next week’s cut list** (what you will *not* do)

Milestones:
- 3 packaged prototypes
- GDD v1 completed
- Vertical slice skeleton built
- VR interaction sandbox tested
- Vertical slice performance budget achieved
- Store page + press kit draft ready

---

## Appendix A — What universities implicitly teach (and you must replicate)

University programs repeatedly emphasize:
- **CS foundations + math/physics** plus hands-on game projects (DigiPen, RIT).  
- **Discipline tracks** similar to real studios (Utah EAE tracks).  
- **Interactive media foundations** (USC) and professional practice (SMU).  

You can’t do all specialties at once solo, but you must be “minimally competent” in each area.

---

## Appendix B — Solo Developer Skill Checklist (the “hidden curriculum”)

- **Version control & backups**
- **Debugging and profiling**
- **Scoping & ruthless prioritization**
- **Asset budgets & performance constraints (especially VR)**
- **Playtesting & iteration loops**
- **Writing & communication (docs, patch notes, store copy)**
- **Community and marketing ops**
- **Basic business admin (store setup, taxes, legal hygiene)**
- **Accessibility basics**
- **Release discipline (build reproducibility)**

---

## Appendix C — Recommended folder additions to your repo

Your current suite already has `study-plans/templates`. Add:

- `study-plans/game-development/study-plan.md` (this file)
- `resources/game-development/` with:
  - `courses.md`
  - `textbooks.md`
  - `youtube.md`
  - `practice-sites.md`
  - `curated-lists.md`
  - `university-curricula.md`

If you want, these resource lists can later be auto-populated by the suite’s “resource-scrapers” tool category.

