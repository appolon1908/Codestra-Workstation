# Codestra-Workstation — Architecture Charts

> Repository: `appolon1908/Codestra-Workstation`
> Baseline branch: `feat/windows-professional-workstation-20260926`
> Repository-local visual architecture. Update these diagrams when implementation or authority changes.

## 1. System context
```mermaid
flowchart LR
 A["Codestra operators / machines"] --> B["Workstation scripts + profiles"]
 B --> R["Codestra-Workstation<br/>Reusable workstation configuration authority"]
 R --> S["desktop policy/config"]
 R --> D["Windows hosts / approved apps"]
```

## 2. Internal component architecture
```mermaid
flowchart TB
 I["Entrypoint / UI / API / CLI"] --> P["Identity, policy, validation"]
 P --> C["Core domain / orchestration"]
 C --> S["State / configuration / persistence"]
 C --> A["Adapters / integrations"]
 A --> X["Approved dependencies"]
 C --> O["Metrics, logs, traces, audit"]
```

## 3. Critical flow
```mermaid
sequenceDiagram
 participant U as Caller
 participant B as Codestra-Workstation
 participant P as Policy
 participant C as Core
 participant S as State
 participant X as Dependency
 U->>B: Request / event / action
 B->>P: Authenticate + validate
 P-->>B: Decision
 B->>C: Detect host, apply idempotent profile and verify
 C->>S: Read / persist
 C->>X: Bounded integration
 X-->>C: Result / readback
 C-->>U: Normalized response
```

## 4. Deployment and promotion
```mermaid
flowchart LR
 F["Feature branch"] --> T["Tests / validation"]
 T --> PR["Pull request + review"]
 PR --> CI["CI green"]
 CI --> ST["Staging / isolated verification"]
 ST --> EX["Exact-SHA certification"]
 EX --> G{"Production approval?"}
 G -- No --> ST
 G -- Yes --> P["Production promotion"]
 P --> H["Health/readiness + rollback check"]
```

## 5. Observability and recovery
```mermaid
flowchart LR
 R["Codestra-Workstation"] --> M["Metrics"]
 R --> L["Logs / audit"]
 R --> T["Traces / correlation"]
 M --> O["Observability stack"]
 L --> O
 T --> O
 O --> A["Dashboards / alerts"]
 R --> B["Backup / config snapshot"]
 B --> RR["Restore / rollback rehearsal"]
```

## Ownership notes
- **Role:** Reusable workstation configuration authority
- **Primary boundary:** Workstation scripts + profiles
- **State/config:** desktop policy/config
- **Dependencies/consumers:** Windows hosts / approved apps
- Cross-repository effects must use reviewed contracts; production effects remain separately gated.
