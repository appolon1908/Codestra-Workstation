# Codestra API Workstation

Workstation ID: `codestra-api-workstation-v1`

## Authority

- GitHub: code, contracts, CI and release evidence.
- Linear: execution status.
- Notion: architecture, decisions and runbooks.
- Lucid: flowcharts, system maps and user journeys.
- Middleware V3: runtime command/effect authority.
- N8N: synchronization/reconciliation worker only.

Canonical public path:

```text
Internet / Apps
      |
    Caddy
      |
     Kong
      |
Middleware V3 :8095
      |
governed service APIs/adapters
```

## Workstation links

- Linear project: https://linear.app/passion-fruit/project/codestra-api-workstation-cross-repo-readiness-ac4681283417
- Linear readiness document: https://linear.app/passion-fruit/document/api-workstation-repo-readiness-matrix-and-execution-plan-f63c2d1d8efd
- Notion: https://app.notion.com/p/3ed7518c3e0681e79abdee00b136209d?pvs=204
- Lucid: https://lucid.app/lucidchart/da85d1b4-a6db-4dff-9286-d66bdcd560db/view
- Registry: `config/api-workstation-registry.v1.json`

## Environment promotion

`development -> testing -> staging -> production`

No production status is inferred from documentation. Exact-head CI, contract tests, auth-negative tests, runtime readiness, staging evidence and rollback proof are required.

## Exposure rule

Application APIs may be public only through approved Caddy/Kong routes. Infrastructure administration, secrets, databases, `/metrics`, and `/internal` surfaces remain private.

## Sync

The current baseline has the same IDs and links recorded in GitHub, Linear, Notion and Lucid.

The future N8N reconciler is plan-only and disabled until credentials, API bindings, idempotency storage, loop prevention and audit evidence are certified. It must not trigger live/provider effects.
