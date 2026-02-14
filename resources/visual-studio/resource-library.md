# Visual Studio Community (2026 / VS 2022) – Resource Library (Solo Unreal Dev)

This library is curated for returning developers who want to get productive quickly in **Visual Studio Community** (current branding: **Visual Studio 2026**) while also staying compatible with **Unreal Engine 5.7’s supported toolchain**.

> **Compatibility note (Unreal Engine 5.7):** Epic’s binary UE 5.7 integration table lists **Visual Studio 2022 (17.8+)** and recommends **17.14**. Visual Studio 2026 may work in some setups (especially source builds), but expect edge cases. Keep VS 2022 installed side‑by‑side if you want the smoothest UE 5.7 experience.

---

## A) Fast start (do these in order)

1) **Install & workloads**
- Install “**Game development with C++**” (and optionally “**Desktop development with C++**”) via Visual Studio Installer.
- Install **Visual Studio Tools for Unreal Engine** (UE logging, macro expansion, Blueprint references, UE tests).

2) **Do 3 micro-drills**
- Create a tiny C++ console project (relearn the UI + build pipeline)
- Learn breakpoints + watch + call stack + exception settings
- Clone a repo and commit/push from within VS

3) **Unreal-specific**
- Follow Epic’s UE 5.7 Visual Studio setup guidance and verify compiler/toolset version.

---

## B) Official “getting started” (Microsoft)

- Getting started hub (Community download + tutorials)
- C++ install steps (workloads/components)
- C++ tutorial: create/build/run a console app
- Productivity features guide (shortcuts, navigation, editor features)

---

## C) Debugging (regain speed)

**Microsoft Learn**
- Debugger feature tour
- Debugging for absolute beginners
- Debugging techniques & tools
- Remote debugging (optional but useful)

**YouTube**
- Debugging tips & tricks sessions
- Advanced debugger techniques

---

## D) Git & GitHub inside Visual Studio

**Docs**
- About Git in Visual Studio
- Manage Git repositories (amend/squash/branches)
- Git settings & preferences

**YouTube**
- Git Tooling in Visual Studio (playlist)
- “Mastering Git in Visual Studio” session(s)

---

## E) C++ in Visual Studio (Unreal-oriented)

**Build systems / deps**
- CMake projects in Visual Studio + CMake Presets
- vcpkg + CMake integration

**Code quality**
- C/C++ Code Analysis quickstart + overview
- clang-tidy in Visual Studio
- AddressSanitizer (ASan) for MSVC

**Keep current**
- “What’s new for C++ developers in Visual Studio 2026 (v18.0)” (C++ team blog)

---

## F) Unreal Engine integration (must-haves)

**Microsoft Learn (VS + UE)**
- Install Visual Studio Tools for Unreal Engine
- Quickstart: Visual Studio Tools for Unreal Engine

**Epic docs**
- Setting up Visual Studio for Unreal Engine (compatibility table + settings)
- UE 5.7 Visual Studio setup tutorial (step-by-step)
- Build and run low-level tests in Unreal Engine (ties into test adapters)

---

## G) Best YouTube channels/playlists (watch like a course)

- Microsoft Visual Studio channel
  - Visual Studio Tips & Tricks (playlist)
  - Git Tooling in Visual Studio (playlist)
  - Getting started with GitHub Copilot in Visual Studio (playlist, optional)

- Visual Studio 2026 deep dives (performance & roadmap talks)
  - The Road to Visual Studio 2026
  - Performance Improvements in Visual Studio 2026
  - The Future of Visual Studio

---

## H) Suggested “returning developer” path (2 weeks)

**Week 1 – IDE fluency**
- Day 1: Install workloads + run the C++ console tutorial
- Day 2: Debugger tour + breakpoint/watch/call stack drills
- Day 3: Git clone/branch/commit/push inside VS
- Day 4: Productivity guide (navigation/search/refactor/shortcuts) + practice
- Day 5: Install UE VS tools + open a UE project and verify integration

**Week 2 – Unreal-ready C++ workflows**
- Day 1–2: UE VS tools quickstart (logs/macros/Blueprint refs/tests)
- Day 3: Configure clang-tidy + run one static analysis pass
- Day 4: ASan on a small non-UE sample (learn the loop)
- Day 5: Build/perf basics (Build Insights/build times) and apply one win

---

## I) Common Unreal gotchas (quick fixes)

- **IntelliSense red everywhere / slow indexing:** open the UE-generated `.sln` and let first full index finish; avoid “open folder” for UE work.
- **Toolchain mismatch:** UE 5.7 binary expects VS 2022 (17.8+) tooling; keep VS 2022 installed even if experimenting with VS 2026.
- **Big compile times:** learn Build Insights + unity build implications; iterate in small translation units.
