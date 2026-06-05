# Gitignore Standards

- `gitignore_matrix.json`: repo-type-to-fragment manifest used by `scripts/rollout/plan_repo_upgrade.ps1`.
- `fragments/*.gitignore`: reviewed fragment library for generated artifacts, archives, tools, Unreal, C++, Python, web, docs-only, and QA Live outputs.

The upgrade planner reports missing recommended patterns as `manual_review` actions. It does not rewrite downstream `.gitignore` files; operators merge only reviewed missing patterns and preserve local overrides.
