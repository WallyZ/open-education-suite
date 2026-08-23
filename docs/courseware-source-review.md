# Courseware Source Review

Last reviewed: 2026-05-31

This document keeps a curated source list of open courseware and adjacent learning sites we can use for course-design reference. It is not a catalog mirror. External course links remain links; subject course content should live in the relevant `open-education-*` content repo and must preserve license, attribution, and use boundaries.

## Use Boundary

- Use these sites for learning, comparison, course structure, and linked references.
- Do not copy lectures, assignments, quizzes, videos, slides, transcripts, or images into this repo unless the license explicitly allows it and attribution is preserved.
- Prefer linking from subject repos with `provider`, `url`, `license`, `lastReviewed`, `whyUseful`, and `borrowedPattern` metadata.
- Keep the core suite content-agnostic. Course-specific mappings belong in subject repos such as `F:\dev\open-education-game-development`.

## Course Setup Patterns To Borrow

| Source | Course setup pattern | Resources provided | Borrow for our course objects |
| --- | --- | --- | --- |
| MIT OpenCourseWare | Course pages center on syllabus, calendar, readings, lecture notes, assignments, exams, projects, and downloadable material when available. | Stable course links, faculty/instructor attribution, license notes, video/notes/problem sets depending on course. | Require syllabus, schedule, objectives, readings/videos, assignments, exams/projects, attribution, and license fields. |
| MIT Open Learning Library | Self-paced course cards and course pages focus on interactive practice and immediate feedback without registration. | Interactive exercises, feedback, course descriptions, instructor metadata. | Add formative practice metadata and immediate-feedback requirements to modules. |
| Harvard CS50 | Courses use a strong sidebar/course map: weeks, lectures, notes, shorts, problem sets, practice, final project, academic honesty, staff, FAQ, tools, communities. | Videos, notes, labs/problem sets, practice, final projects, gradebook/certificates/community links. | Add a standard learner navigation model: week/module, lesson, practice, project, policy, tools, support, community, final artifact. |
| Stanford Engineering Everywhere | Archive-style university courses with lecture videos, handouts, assignments, exams, and prerequisites. | Full lecture sequences, downloadable handouts, assignments, exams. | Preserve instructor-style sequence and explicit prerequisites while mapping each topic to mastery objectives. |
| CMU Open Learning Initiative | Learning-engineering course design with pages, activities, practice, checkpoints, and data-informed feedback. | Course catalog, interactive activities, checkpoint assessments, immediate feedback. | Add checkpoint and misconception metadata to every module, not only final tests. |
| OpenStax | Textbook-first structure with chapters, learning objectives, examples, exercises, glossaries, and instructor resources. | Open textbooks, chapters, exercises, figures, instructor/learner resources. | Add textbook-style objective/chapter/exercise mappings and reusable reading packs. |
| OpenLearn | Short free courses with level, estimated hours, activities, quizzes, and badges/certificates on some courses. | Time estimates, levels, activities, quizzes, transcripts and accessible study materials. | Require level, estimated time, activity count, and completion evidence for short courses. |
| Saylor Academy | Course pages use units, learning outcomes, resources, assessments, final exams, and certificate paths. | Units, readings, assessments, final exams, completion/certificate structure. | Add unit-level outcomes, pre/post checks, and final-exam readiness gates. |
| Nand2Tetris | Project ladder from first principles to a complete system, with lectures, tools, and staged projects. | Videos, chapters, software tools, project specs, staged deliverables. | Use project ladders for skills where mastery comes from cumulative construction. |

## Representative Course Link List

These are initial candidates to learn from and cite as external references. The goal is to keep durable links and summary notes, then map useful patterns into our own original courses.

| Provider | Course or catalog | Link | Useful because | Course object notes |
| --- | --- | --- | --- | --- |
| MIT OCW | CMS.608 Game Design | <https://ocw.mit.edu/courses/cms-608-game-design-spring-2014/> | Directly relevant to game-design foundations and critique-driven learning. | Use for game-design syllabus shape, critique/project cadence, and reading/assignment separation. |
| MIT OCW | CMS.611J Creating Video Games | <https://ocw.mit.edu/courses/cms-611j-creating-video-games-fall-2014/> | University-level game creation course with project orientation. | Use for game-production sequencing and team/project expectations. |
| MIT OCW | 6.837 Computer Graphics | <https://ocw.mit.edu/courses/6-837-computer-graphics-fall-2012/> | Core rendering and graphics foundations for game development. | Map to advanced graphics objectives and math/practice dependencies. |
| MIT OCW | 6.006 Introduction to Algorithms | <https://ocw.mit.edu/courses/6-006-introduction-to-algorithms-spring-2020/> | Strong lecture/problem-set/exam structure for rigorous CS topics. | Borrow problem-set and exam gating patterns. |
| MIT OCW | 6.0001 Introduction to Computer Science and Programming in Python | <https://ocw.mit.edu/courses/6-0001-introduction-to-computer-science-and-programming-in-python-fall-2016/> | Full beginner programming sequence with lectures and problem sets. | Useful for onboarding and programming prerequisites. |
| MIT OCW | 6.0002 Introduction to Computational Thinking and Data Science | <https://ocw.mit.edu/courses/6-0002-introduction-to-computational-thinking-and-data-science-fall-2016/> | Bridges programming, modeling, simulation, and data analysis. | Useful for data-science and simulation course paths. |
| MIT OCW | 6.034 Artificial Intelligence | <https://ocw.mit.edu/courses/6-034-artificial-intelligence-fall-2010/> | Classic AI lecture/courseware structure. | Useful for AI course readings, lecture sequencing, and exams. |
| MIT Open Learning Library | 11.132x Design and Development of Educational Technology | <https://openlearninglibrary.mit.edu/courses/course-v1:MITx+11.132x_3+1T2017/about> | Directly relevant to building learning technology. | Use to shape our course-authoring and feedback design. |
| MIT Open Learning Library | Open Learning Library catalog | <https://openlearning.mit.edu/courses-programs/open-learning-library> | Catalog shows self-paced, interactive-feedback course packaging. | Use as reference for immediate-feedback module metadata. |
| Harvard CS50 | CS50x Introduction to Computer Science | <https://cs50.harvard.edu/x/> | Excellent week-by-week learner path, tools, practice, policies, final project, and community support. | Borrow course navigation, tooling links, final project, academic honesty, and FAQ patterns. |
| Harvard CS50 | CS50 2D Game Development | <https://cs50.harvard.edu/games/> | Direct game-development continuation course with hands-on projects. | Use for game-specific project cadence, toolchain notes, and final artifact expectations. |
| Harvard CS50 | CS50 AI | <https://cs50.harvard.edu/ai/> | Project-heavy applied AI continuation course. | Useful for AI objectives, project scaffolds, and automated assessment ideas. |
| Harvard CS50 | CS50 Python | <https://cs50.harvard.edu/python/> | Focused beginner Python course with practice emphasis. | Good model for short bridge courses and remediation tracks. |
| Harvard CS50 | CS50 Web | <https://cs50.harvard.edu/web/> | Project-driven web application course. | Useful for software-development specialization courses. |
| Harvard CS50 | CS50 Cybersecurity | <https://cs50.harvard.edu/cybersecurity/> | Technical/non-technical cybersecurity course framing. | Useful for cybersecurity repo tone, scenarios, and risk tradeoff framing. |
| Harvard CS50 | CS50 SQL | <https://cs50.harvard.edu/sql/> | Focused database course with practical exercises. | Useful for data-science and software-development prerequisites. |
| Stanford SEE | CS106A Programming Methodology | <https://see.stanford.edu/Course/CS106A> | Full archive-style intro programming course. | Use for lecture/assignment/exam progression and prerequisites. |
| Stanford SEE | CS106B Programming Abstractions | <https://see.stanford.edu/Course/CS106B> | Data structures and abstraction course. | Use for software-development and game-systems prerequisites. |
| Stanford SEE | CS107 Programming Paradigms | <https://see.stanford.edu/Course/CS107> | Systems/programming paradigms course. | Use for engine/systems programming prerequisites. |
| Stanford SEE | CS229 Machine Learning | <https://see.stanford.edu/Course/CS229> | Rigorous ML course with lectures and problem sets. | Use for advanced AI/data-science pathways. |
| CMU OLI | Course catalog | <https://oli.cmu.edu/courses/> | Strong model for learning-engineered activities and checkpoints. | Use for checkpoint, practice, and feedback metadata patterns. |
| OpenStax | Subjects catalog | <https://openstax.org/subjects> | Textbook catalog across math, science, business, humanities, and CS-adjacent support. | Use as reading source registry and chapter/objective mapping model. |
| OpenStax | College Algebra 2e | <https://openstax.org/details/books/college-algebra-2e> | Structured objectives, examples, exercises, and review. | Useful for math remediation and game-math prerequisites. |
| OpenStax | Calculus Volume 1 | <https://openstax.org/details/books/calculus-volume-1> | Good chapter/exercise model for rigorous math. | Useful for physics, graphics, and data-science tracks. |
| OpenStax | Introductory Statistics | <https://openstax.org/details/books/introductory-statistics> | Open textbook with exercises and examples. | Useful for data-science foundations and assessment items. |
| OpenLearn | Free courses catalogue | <https://www.open.edu/openlearn/free-courses/full-catalogue> | Shows short-course packaging with levels, hours, activities, and quizzes. | Borrow level/time/activity metadata and accessible self-study framing. |
| Saylor Academy | Computer Science catalog | <https://learn.saylor.org/course/index.php?categoryid=9> | Unit-based free courses with assessments and final exams. | Borrow unit-level outcomes, exam readiness, and certificate-style completion gates. |
| Nand2Tetris | Course | <https://www.nand2tetris.org/course> | Project ladder from logic gates to operating system/applications. | Borrow cumulative project sequence for engine, tooling, and systems courses. |

## Improvements To Pull Into Our Course Model

1. Every course should expose a learner-facing map: overview, prerequisites, outcomes, module/week list, tools, policies, support, and final deliverable.
2. Every module should have videos, readings, practice, checkpoint, misconception targets, and an adaptive next-step handoff.
3. Every external reference should carry source metadata: provider, URL, license/use boundary, why it is useful, and last reviewed date.
4. Every course should separate "learn from this external source" from "our original assessment/project." We can link and learn, but our course assets must be original or properly licensed.
5. Course packages should support both long semester-style courses and short self-paced courses with estimated time, level, and completion evidence.
6. High-quality courses need real support structures: FAQs, academic integrity, tool setup, accessibility notes, community/help links, and project galleries or exemplars.
7. Adaptive teaching should add what static courseware lacks: learner-state diagnosis, misconceptions, spaced review, branch recommendations, practice selection, and per-learner lecture adaptation.
