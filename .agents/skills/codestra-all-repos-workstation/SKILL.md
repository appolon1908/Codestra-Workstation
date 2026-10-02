---
name: codestra-all-repos-workstation
description: Route and execute Codex tasks across the appolon1908 Codestra portfolio. Use for any task that names, compares, audits, changes, tests, or coordinates one or more repositories in the 113-repository workstation.
---

# Codestra All-Repos Workstation

1. Start in `appolon1908/Codestra-Workstation` and read `.codestra/repository-catalog.yaml`.
2. Resolve the user's target repository or repositories exactly. Never substitute a similarly named repo.
3. For each target repo:
   - change into that repository;
   - read its root `AGENTS.md` and any deeper applicable `AGENTS.md`;
   - read `.codestra/repository-profile.yaml` when present;
   - verify `origin` points to `appolon1908/<repo>`;
   - verify current branch, HEAD, dirty state, and remote state before mutation.
4. Use the effective lifecycle mapping from the catalog/profile:
   `development → testing → staging → production`.
   Where a namespace conflict exists, use the declared `testing/environment` or `production/environment` mapping.
5. Keep repositories independently operable. Cross-repo integration must occur through documented APIs, endpoints, events, packages, or contracts.
6. Treat Middleware V3 as optional orchestration unless the target repo explicitly declares it as a runtime dependency.
7. Do not force-push, bypass protected branches, weaken CI, discard another agent's work, or enable live production effects without explicit authorization.
8. Implement code completely, add/update tests, and run the target repository's relevant checks.
9. For cross-repo changes, finish and verify each repo independently. Report exact repository, branch, HEAD, files changed, tests, CI status, and remaining blockers per repo.
10. For portfolio-wide status questions, use the catalog as the inventory authority and live GitHub state as execution truth.
