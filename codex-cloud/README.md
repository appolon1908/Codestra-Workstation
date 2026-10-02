# Codestra All-Repos Codex Cloud Workstation

This directory defines the portfolio workstation for the repositories owned by `appolon1908`.

## Codex Cloud environment

Create one Codex Cloud environment named **Codestra All-Repos Workstation** and select **all repositories** available under the connected `appolon1908` GitHub account.

Codex Cloud supports environments containing multiple repositories. The environment should use this repository, `appolon1908/Codestra-Workstation`, as the control-plane repository.

### Setup

1. Open **Codex Cloud**.
2. Choose **Work in → Cloud → Select environment → Create environment**.
3. Connect GitHub as `appolon1908` if prompted.
4. Select **All repositories** for the `appolon1908` connection. Expected inventory: **113 repositories**.
5. Let Codex inspect the selected repositories.
6. Use `bash codex-cloud/bootstrap.sh` as the portfolio validation step.
7. Keep internet access at **Package managers** unless a task has a documented need for additional domains.
8. Review setup results and **Publish** the environment.

## Routing rules

- Read `.codestra/repository-catalog.yaml` first for portfolio routing.
- Treat each selected repository as independent software.
- Read that repository's `AGENTS.md` before changing it.
- Prefer `development` for implementation work unless the repository profile says otherwise.
- Promote only forward: `development → testing → staging → production`.
- Eight repositories have Git namespace conflicts and use an effective lifecycle mapping such as `testing/environment` or `production/environment`; use the catalog/profile rather than guessing.
- Never force-push or bypass branch protection.
- Default-deny production side effects.
- Middleware V3 is an optional orchestration boundary; a standalone repository must not depend on Middleware to boot unless that repository's own contract explicitly says otherwise.

## Files

- `environment.yaml` — complete 113-repository Codex Cloud manifest.
- `bootstrap.sh` — validates workstation control files and checked-out repositories.
- `../.codestra/repository-catalog.yaml` — canonical portfolio catalog.
- `../.agents/skills/codestra-all-repos-workstation/SKILL.md` — reusable Codex routing workflow.
