# Game Development Resource Library (Solo Unreal + VR-ready)

A curated, **high-signal** library of learning resources for a solo developer building in **Unreal Engine** with **VR as a first-class constraint**.

Use this as the companion to: `study-plans/game-development/study-plan.md`

---

## How to use this library

### Tags
- **[Core]** = highest ROI / anchor resource
- **[Practice]** = hands-on, step-by-step
- **[Reference]** = look things up while building
- **[Deep Dive]** = advanced; use when you hit the ceiling
- **[Community]** = feedback, troubleshooting, postmortems

### The “don’t drown” rule
Pick **one Core per skill area**, then add **one Practice** resource. Don’t stack 10 courses at once.

### Recommended stack (minimal)
1) **Unreal basics**: Epic learning path + docs
2) **Blueprints + C++ structure**: best practices + gameplay framework
3) **VR input + comfort + perf**: OpenXR input + VR performance testing + Meta comfort docs
4) **Design**: one design book + one playtest method
5) **Marketing**: Steamworks assets rules + one marketing strategy source

### YouTube watchlist (UE 5.7)
- See: `resources/game-development/youtube-ue57.md`
- See (suite internal list): `open-education-suite/resources/youtube/unreal-engine-5.7-blueprints-cpp-vr.md`


---

## 1) University program guides (curriculum reality check)

These are useful to validate you’re covering what formal programs teach (CS fundamentals, math/physics, design documentation, repeated team projects, production).

- DigiPen — BS in Computer Science and Game Design (overview)
  - https://www.digipen.edu/academics/game-design-and-development-degrees/bs-in-computer-science-and-game-design
- DigiPen — Sample Course Sequence (see how it layers programming + projects)
  - https://www.digipen.edu/academics/game-design-and-development-degrees/bs-in-computer-science-and-game-design/sample-course-sequence
- DigiPen — Course Catalog PDF (use for topic lists like AI, physics, rendering, production)
  - https://www.digipen.edu/sites/default/files/public/docs/digipen-course-catalog-2025-2026.pdf
- RIT — Game Design & Development BS (program expectations)
  - https://www.rit.edu/study/game-design-and-development-bs
- RIT — GAMEDES BS Flowchart PDF (course sequencing)
  - https://www.rit.edu/computing/sites/rit.edu.computing/files/docs/22-23%20GAMEDES-BS%20Flowchart_131.final_.pdf
- University of Utah — EAE (tracks mirror real roles: design/engineering/production/tech art)
  - https://games.utah.edu/current-students/meae/
  - Track pages (browse the “coursework” pages):
    - Engineering: https://games.utah.edu/prospective-students/master-of-entertainment-arts-and-engineering/meae-game-engineering-track-coursework/
    - Design: https://games.utah.edu/meae-game-design-track-coursework/
    - Production: https://games.utah.edu/prospective-students/master-of-entertainment-arts-and-engineering/meae-game-production-track-coursework/
    - Technical Art: https://games.utah.edu/prospective-students/master-of-entertainment-arts-and-engineering/meae-technical-art-track-coursework/
- USC — Interactive Media & Games Division (degree ecosystem + course lists)
  - Division overview: https://catalogue.usc.edu/content.php?catoid=16&navoid=6181
  - Example program page: Game Design Minor: https://catalogue.usc.edu/preview_program.php?catoid=12&poid=12596
- SMU Guildhall — game dev degrees + specialization tracks
  - https://www.smu.edu/guildhall
  - Academics: https://www.smu.edu/guildhall/academics
  - Master’s cohorts/courses: https://www.smu.edu/guildhall/academics/game-development-programs/mit-cohorts-and-courses

**How to use these:**
- Build a checklist of topics they cover (CS, math, physics, AI, UI, production, design docs).
- Compare your backlog against that checklist once per quarter.

---

## 2) Ideas → a coherent game (ideation + synthesis)

### Frameworks & methods
- **[Core] MDA framework (Mechanics–Dynamics–Aesthetics)** — helps map “rules” → “feel.”
  - Search terms: “MDA framework Hunicke LeBlanc Zubek paper PDF”
- **[Core] Pillars + player verbs** (practical design decomposition)
  - Use: define 3–5 pillars, then a list of verbs, then build features only if they strengthen pillars.

### Books (pick 1–2 total)
- **[Core] The Art of Game Design** (Jesse Schell) — broad design vocabulary + lenses.
- **[Core] Level Up!** (Scott Rogers) — pragmatic design and production mindset.
- **[Deep Dive] Rules of Play** (Salen & Zimmerman) — strong theory foundation.

### Practice
- **[Practice] Game jams (even solo)** — fastest ideation-to-playable training.
  - itch.io game jams: https://itch.io/jams

---

## 3) GDD + documentation that survives iteration

### What to learn
- Writing systems as **inputs → state → outputs (feedback)**
- Documenting **rules, exceptions, and tuning knobs**
- Converting “story” into **content production rules**

### Tools
- **[Core] Your suite templates**
  - `study-plans/templates/study-plan-template.md`
  - Keep GDD modular: core loop, combat, interaction, UI, content rules, performance budgets.

### Examples / inspiration
- GDD examples (good and bad) are easiest found by searching:
  - “GDD example PDF” + “postmortem” + “vertical slice checklist”

---

## 4) Planning + solo production skills

### Core skills
- Scoping, milestone slicing (prototype → vertical slice → production)
- Risk register + mitigation
- Backlog hygiene (definition of done, acceptance tests)

### Resources
- **[Core] Steamworks docs early** (because store requirements shape your asset pipeline)
  - Store assets: https://partner.steamgames.com/doc/store/assets/standard
  - Asset rules: https://partner.steamgames.com/doc/store/assets/rules
- **[Practice] Agile for solo**
  - Use a 1-week sprint cadence with a “packaged build” requirement.

---

## 5) Unreal Engine fundamentals

### Starting point
- **[Core] Epic Learning Path: Welcome to Game Development**
  - https://dev.epicgames.com/community/learning/paths/OR/welcome-to-game-development

### Reference docs you’ll use constantly
- **[Core] Gameplay Framework (Actor/Pawn/Controller/GameMode, etc.)**
  - https://dev.epicgames.com/documentation/en-us/unreal-engine/gameplay-framework-in-unreal-engine
- **[Reference] Blueprint best practices**
  - https://dev.epicgames.com/documentation/en-us/unreal-engine/blueprint-best-practices-in-unreal-engine
- **[Core] Best Practices for Blueprints and C++**
  - https://dev.epicgames.com/community/learning/tutorials/7399/unreal-engine-best-practices-for-blueprints-and-c

---

## 6) Coding: Blueprints + C++ (the hybrid path)

### What to learn (in order)
1) Blueprint architecture: components, interfaces, data assets
2) Gameplay framework in C++: AActor/APawn/ACharacter, PlayerController, GameMode
3) Performance boundaries: what to move from BP → C++ and why

### Unreal-specific references
- **[Core] Gameplay Framework**
  - https://dev.epicgames.com/documentation/en-us/unreal-engine/gameplay-framework-in-unreal-engine
- **[Core] Enhanced Input (runtime remapping, contexts, actions)**
  - https://dev.epicgames.com/documentation/en-us/unreal-engine/enhanced-input-in-unreal-engine
- **[Deep Dive / RPG] Gameplay Ability System (GAS)**
  - Official overview: https://dev.epicgames.com/documentation/en-us/unreal-engine/gameplay-ability-system-for-unreal-engine
  - “Understanding GAS”: https://dev.epicgames.com/documentation/en-us/unreal-engine/understanding-the-unreal-engine-gameplay-ability-system
  - Community deep dive (very practical): https://github.com/tranek/GASDocumentation

### C++ skill foundations (non-Unreal)
- **[Core] Learn C++ fundamentals**
  - https://www.learncpp.com/

### Game programming architecture (general)
- **[Core] Game Programming Patterns** (Robert Nystrom) — architecture patterns with examples.
  - https://gameprogrammingpatterns.com/

---

## 7) VR in Unreal (input + comfort + performance)

### Input and platform abstraction
- **[Core] OpenXR input in Unreal**
  - https://dev.epicgames.com/documentation/en-us/unreal-engine/openxr-input-in-unreal-engine

### Comfort & UX best practices
- **[Core] Meta comfort best practices**
  - https://developers.meta.com/horizon/design/comfort/
  - Overview: https://developers.meta.com/horizon/design/bp-overview/

### Performance (VR is unforgiving)
- **[Core] Epic: VR Performance Testing**
  - https://dev.epicgames.com/documentation/en-us/unreal-engine/vr-performance-testing-in-unreal-engine
- **[Core] Meta performance guidelines (common bottlenecks)**
  - https://developers.meta.com/horizon/documentation/native/pc/dg-performance-guidelines/

### Shipping to Quest (quality gates)
- **[Reference] Meta Quest VRC guidelines**
  - https://developers.meta.com/horizon/resources/publish-quest-req/

---

## 8) UI / UX (including VR UI)

### What to learn
- Information hierarchy and readability
- Input affordances (hands/controllers)
- Diegetic UI vs 2D panels vs wrist/helmet UI
- Accessibility basics (remapping, text size, comfort settings)

### Resources
- **[Core] Meta comfort + design pages** (treat as “minimum bar”)
  - https://developers.meta.com/horizon/design/comfort/
  - https://developers.meta.com/horizon/design/bp-overview/
- **[Deep Dive] VR UI guideline survey paper (research-backed)**
  - https://arxiv.org/html/2508.09358

---

## 9) Visuals: 3D art pipeline + generative workflows

### Traditional pipeline (you need the basics, even if outsourcing later)
- Blockout → modular kit → hero props → materials → lighting → LODs
- Skills to acquire:
  - Modeling + UVs + texel density
  - PBR materials (roughness/metalness discipline)
  - LODs + instancing + performance budgets

### Unreal-side rendering / lighting
- Keep a “worst-case performance map” and profile it weekly.

### Generative images (LLM/diffusion prompting)
- **[Core] Stability: Stable Diffusion 3.5 prompt guide**
  - https://stability.ai/learning-hub/stable-diffusion-3-5-prompt-guide
- **[Core] ComfyUI: Conditioning docs**
  - https://blenderneko.github.io/ComfyUI-docs/Core%20Nodes/Conditioning/

**Recommended use cases for AI visuals (high ROI):**
- Concept exploration + style bible
- Storyboard frames for trailers
- UI/branding exploration

### Generative video (for previs / marketing)
- **[Core] Runway Gen-3 prompting guide**
  - https://help.runwayml.com/hc/en-us/articles/30586818553107-Gen-3-Alpha-Prompting-Guide
- **[Reference] Stability: Stable Video Diffusion**
  - Product page: https://stability.ai/stable-video
  - Research page: https://stability.ai/research/stable-video-diffusion-scaling-latent-video-diffusion-models-to-large-datasets

---

## 10) Audio (minimum viable competence)

### What to learn
- Building a repeatable SFX pipeline
- Spatial audio basics (VR needs this)
- Loudness sanity checks and avoiding fatigue

### Suggested approach
- Start with “functional” audio early (so you tune gameplay to feedback), then replace later.

---

## 11) PR + Marketing (the part that makes shipping matter)

### Steam (required knowledge if you ship there)
- **[Core] Store graphical assets**
  - https://partner.steamgames.com/doc/store/assets/standard
- **[Core] Graphical asset rules**
  - https://partner.steamgames.com/doc/store/assets/rules

### Press kit
- **[Core] presskit()**
  - https://dopresskit.com/

### Marketing strategy (indie practical)
- **[Core] HowToMarketAGame — coming-soon timing**
  - https://howtomarketagame.com/2025/03/10/when-should-i-post-my-steam-coming-soon-page/

### Recommended marketing “minimum loop”
- A monthly **playable build** + short clip
- A single “pitch paragraph” that stays consistent
- Screenshots/trailer storyboard generated from your prompt library

---

## 12) Communities (debugging + reality checks)

- Unreal Engine forums (good for engine-specific questions)
  - https://forums.unrealengine.com/
- r/gamedev (postmortems, marketing discussions, production realities)
  - https://www.reddit.com/r/gamedev/
- r/unrealengine (pipeline + UE-specific tips)
  - https://www.reddit.com/r/unrealengine/

---

## 13) Suggested resource usage by phase (maps to your study plan)

### Phase 1 (micro-prototypes)
- Epic learning path
- Blueprint best practices
- Gameplay framework

### Phase 2 (GDD + scope)
- One design book
- University program checklists (extract topics)
- Steamworks assets/rules (start aligning visuals early)

### Phase 3–4 (systems + C++)
- Best practices BP/C++
- Enhanced Input
- Gameplay Ability System (if your game is ability-heavy)

### Phase 5 (VR UX + perf)
- OpenXR input
- VR performance testing
- Meta comfort guidelines + VRC

### Phase 6 (marketing)
- Steamworks docs
- presskit()
- HowToMarketAGame key articles

---

## Appendix: Quick “starter picks” (if you want the shortest list)

- Epic: Welcome to Game Development (Core)
- Epic: Gameplay Framework (Core)
- Epic: Blueprint Best Practices (Reference)
- Epic: Best Practices for Blueprints and C++ (Core)
- Epic: OpenXR Input (Core)
- Epic: VR Performance Testing (Core)
- Meta: Comfort Guidelines (Core)
- Steamworks: Store Assets + Rules (Core)
- presskit() (Core)
- One design book (Schell or Rogers) (Core)

