# Seizu Helm Chart

This chart deploys [Seizu](https://github.com/mappedsky/seizu), a React and Python frontend for Neo4j security graph data.

## Install

```sh
helm install seizu ./charts/seizu \
  --set seizu.neo4j.uri=bolt://neo4j.default.svc.cluster.local:7687
```

## Configuration Notes

Seizu needs these external dependencies:

- A reachable Neo4j database. This chart does not deploy Neo4j by default.
- A report-store backend. By default this chart configures Seizu to use DynamoDB with `seizu.reportStore.backend=dynamodb`. Configure the table with `seizu.reportStore.dynamodb.tableName`, `seizu.reportStore.dynamodb.region`, and optionally `seizu.reportStore.dynamodb.endpointUrl` for DynamoDB-compatible endpoints such as DynamoDB Local. To use SQL instead, set `seizu.reportStore.backend=sqlmodel` and provide `seizu.reportStore.sqlDatabaseUrl`.

Authentication is disabled by default for a basic install by setting `DEVELOPMENT_ONLY_REQUIRE_AUTH=false`. For production, set `seizu.auth.developmentOnlyRequireAuth=true`, configure OIDC/JWT values, and provide `secrets.data.reportQuerySigningSecret` and `secrets.data.sessionTokenEncryptionKey`.

## Upgrading to Seizu 4.0.0

Seizu 4.0.0 has several operationally significant breaking changes:

- Rename Cartography credentials before upgrading: `NIST_NVD_TOKEN`, `CROWDSTRIKE_CLIENT_ID`, `CROWDSTRIKE_CLIENT_SECRET`, `PAGERDUTY_API_KEY`, and `OKTA_API_KEY` now require the `CARTOGRAPHY_` prefix. There is no fallback for the old names.
- `scheduledQueries.modules` has been replaced by `seizu.workflows.activityModules`. Do not include the removed `reporting.scheduled_query_modules.workflow` or `.temporal` modules. The chart now emits `WORKFLOW_ACTIVITY_MODULES`; Seizu's deprecated `SCHEDULED_QUERY_MODULES` fallback is not emitted.
- Code-defined workflows such as `cartography_sync`, `cve_repo_report`, and `cve_dependency_remediation` are top-level activity types. API clients creating definitions must stop sending `type: workflow` with `parameters.workflow`, or the old `temporal` action. Stored definitions are migrated when read, but new saves in the old shape are rejected.
- Cartography activities now use ordered `module_runs`. The old `modules` and `pipeline` fields are removed. `create-indexes` and `analysis` must be selected explicitly for new definitions.
- Add `workflows:read`, `workflows:write`, and `workflows:delete` to custom roles. The corresponding `scheduled_queries:*` grants are only a one-release compatibility bridge.
- Multi-stage, cross-stage, and chained workflows are not exposed by the legacy `/api/v1/scheduled-queries/*` endpoints. Move automation to `/api/v1/workflows/*`.

## Configurable workflows

Seizu 4 uses Temporal-backed configurable workflows for scheduling. Configure activity modules and workflow execution limits through `seizu.workflows.*`, the Temporal connection through `seizu.temporal.*`, and deploy the orchestration worker with:

```sh
helm upgrade --install seizu ./charts/seizu \
  --set temporalWorker.enabled=true
```

The old `scheduledQueries` worker remains available for compatibility, but is disabled by default and cannot execute legacy `temporal` actions. Use `extraEnv`, `extraEnvFrom`, and `secrets` to provide cloud credentials, Slack tokens, or report-store secrets.

## Chat assistant

The LangGraph-backed chat assistant is disabled by default. Enable it with `seizu.chat.enabled=true`, an LLM provider, and checkpoint storage:

```sh
helm upgrade --install seizu ./charts/seizu \
  --set seizu.chat.enabled=true \
  --set seizu.chat.llm.provider=litellm \
  --set seizu.chat.llm.model=anthropic/claude-sonnet-4-5 \
  --set secrets.data.anthropicApiKey=<key>
```

- `seizu.chat.llm` configures the model, generation limits, per-turn context caps, and optional role-specific model overrides (planner/worker/verifier/synthesizer/economy).
- `seizu.chat.orchestrator` and `seizu.chat.run` control the plan/dispatch/verify orchestration and the per-run token/cost budgets.
- `seizu.chat.checkpoint` selects the LangGraph checkpoint backend: DynamoDB (default, with optional TTL, compression, and S3 offload for large payloads) or PostgreSQL (`backend=postgres`, with credentials in `secrets.data.chatCheckpointDatabaseUser`/`chatCheckpointDatabasePassword`).
- Provider API keys go in `secrets.data` (`chatLlmApiKey`, or the per-provider `openaiApiKey`, `anthropicApiKey`, `geminiApiKey`, `googleApiKey`, `deepseekApiKey`).

## Scheduled chats

Scheduled chats run the chat agent on a recurring schedule as a headless session. `scheduledChats.enabled=true` deploys the worker (`python -m reporting.scheduled_chats`) and enables the API routes and UI. It requires `seizu.chat.enabled=true`. Multiple replicas are safe: a distributed lock guarantees one run per due window.

## Temporal workflows

Configurable workflows and code-defined activities (for example `cve_repo_report`, `cve_dependency_remediation`, and `cartography_sync`) are executed by the Temporal worker. This chart does not deploy a Temporal server; point `seizu.temporal.address` at one, then set `temporalWorker.enabled=true` to deploy the worker (`python -m reporting.temporal_worker`). Use `seizu.temporal.enabledWorkflows` to allowlist code-defined activity types.

The CVE dependency remediation workflow additionally needs `secrets.data.remediationGithubToken`, a sandbox provider (`secrets.data.sandboxApiKey` for E2B, or `seizu.sandbox.domain` for self-hosted), and a coding-agent credential (`seizu.sandbox.agent.apiKeyCommand` recommended, or `secrets.data.sandboxAgentApiKey`); tune it via `seizu.remediation.*`.

## Cartography sync worker

Scheduled Cartography syncs require both the Seizu Temporal orchestration worker and the dedicated credential-bearing activity worker:

```sh
helm upgrade --install seizu ./charts/seizu \
  --set temporalWorker.enabled=true \
  --set cartographyWorker.enabled=true \
  --set-string cartographyWorker.secrets.data.CARTOGRAPHY_NIST_NVD_TOKEN=<key>
```

The dedicated worker defaults to `ghcr.io/mappedsky/seizu-cartography:4.1.0`. It contains Cartography 0.139.0 and the thin Temporal activity worker, and does not receive the main Seizu Secret.

- `seizu.cartography.*` configures the task queue, module allowlist, module timeout/wait, and retry count used by the web and Temporal workers.
- `cartographyWorker.neo4jUri` defaults to `seizu.neo4j.uri`. Neo4j credentials belong in `cartographyWorker.secrets.data.CARTOGRAPHY_NEO4J_USER` and `CARTOGRAPHY_NEO4J_PASSWORD`.
- `cartographyWorker.config` lists supported non-secret worker variables using their exact environment names, including SDK profiles/paths, StatsD, `LOG_LEVEL`, and `CARTOGRAPHY_BIN`. File-valued options can be mounted at the fixed image paths with `cartographyWorker.extraVolumes` and `extraVolumeMounts`.
- `cartographyWorker.secrets.data` lists every Cartography 0.139.0 credential variable accepted by Seizu 4.0.0. For an externally managed Secret, set `cartographyWorker.secrets.create=false` and `cartographyWorker.secrets.existingSecret`; its keys must use the listed `CARTOGRAPHY_*` names.
- `seizu.cartography.enabledModules` is empty by default, allowing all registered modules. Set it to a reviewed list to enforce the same allowlist in the UI, dispatcher, and credential-bearing worker.

The registry supports all Cartography 0.139.0 intelligence modules: `airbyte`, `aibom`, `anthropic`, `aws`, `azure`, `bigfix`, `circleci`, `cloudflare`, `crowdstrike`, `cve`, `cve_metadata`, `databricks`, `digitalocean`, `docker_scout`, `duo`, `gcp`, `github`, `gitlab`, `googleworkspace`, `gsuite`, `jamf`, `jumpcloud`, `kandji`, `keycloak`, `kubernetes`, `lastpass`, `microsoft`, `oci`, `okta`, `ontology`, `openai`, `pagerduty`, `salesforce`, `scaleway`, `semgrep`, `sentry`, `sentinelone`, `slack`, `snipeit`, `socketdev`, `spacelift`, `subimage`, `syft`, `tailscale`, `tenable`, `trivy`, `ubuntu`, `vercel`, `workday`, and `workos`, plus `create-indexes` and `analysis`.

## Sandbox delegation

`seizu.sandbox.enabled=true` enables the `sandbox__delegate` chat tool for isolated code execution. Sandboxes are network-isolated by default (`seizu.sandbox.allowInternet=false`).
