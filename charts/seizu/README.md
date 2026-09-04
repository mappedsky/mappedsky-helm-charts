# Seizu Helm Chart

This chart deploys [Seizu](https://github.com/mappedsky/seizu), a React and Python frontend for Neo4j security graph data.

Chart `0.5.0` tracks Seizu `5.2.0`.

## Install

```sh
helm install seizu ./charts/seizu \
  --set seizu.neo4j.uri=bolt://neo4j.default.svc.cluster.local:7687 \
  --set seizu.reportStore.sqlDatabaseUrl=postgresql://postgres.default.svc.cluster.local:5432/seizu \
  --set secrets.data.sqlDatabaseUser=seizu \
  --set secrets.data.sqlDatabasePassword=<password>
```

## Configuration Notes

Seizu needs these external dependencies:

- A reachable Neo4j database. This chart does not deploy Neo4j.
- **PostgreSQL.** Seizu 5 stores every application record there and has no other backend. Set `seizu.reportStore.sqlDatabaseUrl` without credentials, and supply `secrets.data.sqlDatabaseUser` / `secrets.data.sqlDatabasePassword`. A second database for LangGraph chat checkpoints (`seizu.chat.checkpoint.databaseUrl`) is recommended whenever chat is enabled, so its migrations, retention and backups stay independent.
- **A Temporal server**, for anything beyond a read-only web deployment. This chart does not deploy Temporal; point `seizu.temporal.address` at one and set `temporalWorker.enabled=true`.

**Authentication is required by default** (`seizu.auth.developmentOnlyRequireAuth: true`, matching Seizu's own default). A working install therefore also needs:

- A login path: `seizu.auth.jwksUrl` for bearer-JWT clients, and/or `seizu.auth.oidcAuthority` + `seizu.auth.oidcClientId` (+ `secrets.data.oidcClientSecret`) for the browser flow.
- `secrets.data.reportQuerySigningSecret` (`openssl rand -hex 64`) and `secrets.data.sessionTokenEncryptionKey` (`openssl rand -base64 32`). Seizu reads both lazily, so a pod missing them starts healthy and fails on the first request that needs them — the chart's install notes warn when they are empty.

Despite its name, `developmentOnlyRequireAuth` is the production setting: the `developmentOnly` prefix means only a development deployment should turn it *off*. Setting it `false` disables authentication entirely and serves every request as `seizu.auth.developmentOnlyAuthUserEmail`.

`secrets.extraData` writes arbitrary keys into the same Secret verbatim, for credentials the chart has no named field for (external MCP proxy tokens, scheduled-query action module credentials, cloud SDK keys).

## Values-file type hazards

Seizu reads every setting through `int_env()` / `float_env()` / `str_env()`, so a
value that YAML mangles becomes a crashloop or a silent misconfiguration rather
than a Helm error. Two cases have bitten this chart, and both are now handled in
the templates rather than by quoting defaults:

- **Large numbers.** Helm parses unquoted YAML numbers in a values file as
  float64, and Go renders anything at or above 1e6 in scientific notation, so
  `contextMaxTokens: 1000000` used to reach the container as `"1e+06"` and
  `int_env()` rejected it at import. (`--set` was never affected: it yields
  int64.) Every environment value now renders through the `seizu.envValue`
  helper, which formats integral numbers as integers and fractions at fixed
  precision, so any magnitude is safe unquoted.
- **`OFF` is a YAML boolean.** `seizu.neo4j.notificationsMinSeverity: OFF` parses
  as `false` under YAML 1.1. The template maps the boolean back to the literal,
  so `OFF`, `"OFF"` and `off` all reach Seizu as `OFF`.

**When adding a setting to `templates/configmap.yaml`, render it with
`{{ include "seizu.envValue" .Values.… }}` rather than `| quote`.** `join` and
`toJson` already produce strings and stay as they are.

Values that are strings to Seizu stay quoted in `values.yaml`
(`seizu.remediation.ghVersion`, `seizu.sandbox.agent.credentialProxyMaxBudget`),
and a secret whose value begins with a YAML indicator character (`*`, `&`, `!`,
`%`, `@`, `` ` ``) must be quoted like any other YAML scalar.

## Upgrading to Seizu 5.x

Read Seizu's own [upgrade guide](https://github.com/mappedsky/seizu/blob/main/docs/root/install/upgrading.md) before deploying; the storage cutover in 5.0.0 is not reversible. Chart-specific changes:

### Chart default changes

- **`seizu.auth.developmentOnlyRequireAuth` now defaults to `true`.** Earlier chart versions shipped `false`, serving every request unauthenticated as `testuser`. Deployments that relied on that default must now either configure authentication (above) or set it back to `false` explicitly. This is a chart change, not a Seizu one — Seizu has always defaulted to requiring auth.

### Removed values

| Removed | Replacement |
|---|---|
| `seizu.reportStore.backend`, `seizu.reportStore.dynamodb.*` | PostgreSQL only. Use `seizu.reportStore.sqlDatabaseUrl`. |
| `seizu.chat.checkpoint.backend`, `.tableName`, `.ttlSeconds`, `.enableCompression`, `.s3Bucket`, `.s3EndpointUrl`, `.s3KeyPrefix` | PostgreSQL only. Use `seizu.chat.checkpoint.databaseUrl`. |
| `seizu.chat.llm.contextMaxChars` | `seizu.chat.llm.contextMaxTokens` (default 40,000). Context is budgeted in tokens against the model's own window. |
| `scheduledChats.*` (worker Deployment) | `seizu.chat.schedules.*`. Scheduled chats are reconciled into Temporal Schedules by `temporalWorker`; `python -m reporting.scheduled_chats` no longer exists. |
| `scheduledQueries.*` (worker Deployment) | `seizu.workflows.*`. Scheduled queries are projected into workflows and executed by `temporalWorker`. Running the old poll loop alongside it would dispatch every action twice. |
| `seizu.reportStore.snowflakeMachineId` | None. Seizu 5.2.0 generates record ids as UUIDv7, which needs no per-replica coordination. |

Seizu's startup **refuses** `REPORT_STORE_BACKEND`, `CHAT_CHECKPOINT_BACKEND` and the removed DynamoDB/S3 settings, even holding their old SQL-selecting values, so leaving them in a values file fails the pod rather than being ignored.

### Defaults that changed meaning

A value carried over from a 4.x values file still pins the old intent:

- `seizu.chat.llm.maxTokens` and `seizu.chat.orchestrator.plannerMaxTokens` now default to `0`, meaning "derive from the model". The old `4096` starves the planner on a reasoning model and collapses every plan to a single step.
- `seizu.chat.run.tokenBudget` and `seizu.chat.run.maxLlmCalls` now default to `0` (derive from the model and the plan).
- `seizu.chat.run.costBudgetUsd` now defaults to `2.0` where it was unlimited. This is the runaway guard; raise it deliberately.
- `seizu.chat.orchestrator.maxParallel` is `8`, matched to `maxExpansion`.

### New in 5.1.0

- `seizu.mcp.graphQuery.rejectUnindexed` (default `true`) makes `graph__query` refuse a plan Neo4j reports a performance notification for, or whose largest cardinality estimate exceeds `seizu.mcp.graphQuery.unindexedMaxEstimatedRows` (100,000). **A query that used to run may now be rejected with `query_plan_rejected`.** Both settings must match on the web service and the Temporal worker; the shared ConfigMap does that automatically.
- `seizu.chat.llm.routerModel` and `seizu.chat.llm.workerSummaryModel` give those two stages their own deployment models.
- `seizu.chat.llm.model` is no longer required when an enabled default model profile supplies a complete model snapshot. Startup now validates every enabled profile's model ids, on the Temporal worker too — a worker configured with a model LiteLLM cannot resolve refuses to start.
- Model profiles seed and export as ordinary configuration (`model_profiles:` in a seed file, applied with `seizu seed`). The chart does not seed configuration; run the CLI against the deployed API.

### New in 5.2.0

- `seizu.reportStore.snowflakeMachineId` is removed. Seizu now generates record ids as UUIDv7 rather than Snowflake ids, so nothing has to be unique per replica any more and `SNOWFLAKE_MACHINE_ID` is no longer read. Unlike the 5.0.0 storage settings, an unknown environment variable is ignored rather than refused, so a values file still carrying the key deploys — it just does nothing. Ids generated before the upgrade are untouched.

## Chat assistant

The chat assistant is disabled by default. Every turn runs as a Temporal workflow and is streamed from an append-only event log, so enabling it requires an LLM provider, a PostgreSQL checkpoint database, and a reachable Temporal server with a worker:

```sh
helm upgrade --install seizu ./charts/seizu \
  --set seizu.chat.enabled=true \
  --set seizu.chat.llm.provider=litellm \
  --set seizu.chat.llm.model=anthropic/claude-sonnet-4-5 \
  --set seizu.chat.checkpoint.databaseUrl=postgresql://postgres:5432/seizu-chat-checkpoints \
  --set seizu.temporal.address=temporal.default.svc.cluster.local:7233 \
  --set temporalWorker.enabled=true \
  --set secrets.data.anthropicApiKey=<key>
```

- `seizu.chat.llm` configures the model, generation limits, context budgeting against the model's window, prompt caching, history compaction, and per-stage model and reasoning-effort overrides (router/planner/worker/workerSummary/verifier/sandbox/synthesizer/economy).
- `seizu.chat.orchestrator` controls plan/dispatch/verify orchestration, including `distributed.*` — running each independent plan step as its own Temporal activity, placed across the worker fleet.
- `seizu.chat.run` holds the per-run budget. A run is budgeted in **dollars** (`costBudgetUsd`); the token and call ceilings are backstops for a model LiteLLM cannot price.
- `seizu.chat.memory` bounds what earlier sub-agents and earlier turns carry forward.
- `seizu.chat.turn` bounds one interactive turn and how long its event log stays replayable.
- `seizu.chat.schedules` gates scheduled chats (recurring headless runs). There is no separate worker: `temporalWorker` reconciles them into Temporal Schedules.
- `seizu.chat.sessionReap` retires sessions nobody has come back to. **It deletes chat history**, transcript included, and the first sweep after enabling it collects everything already past `idleSeconds`. Off by default.
- `seizu.temporal.maxConcurrentActivities` is the cluster-wide bound on distributed plan steps; `seizu.chat.orchestrator.maxParallel` bounds one turn. Size the former for the fleet before enabling distributed steps at scale.
- Provider API keys go in `secrets.data` (`chatLlmApiKey`, or the per-provider `openaiApiKey`, `anthropicApiKey`, `geminiApiKey`, `googleApiKey`, `deepseekApiKey`).

## Temporal worker

`temporalWorker` runs `python -m reporting.temporal_worker` and owns interactive chat turns, distributed plan steps, scheduled chats, configurable workflows, code-defined activities (`cve_repo_report`, `cve_dependency_remediation`, `cartography_sync`) and the chat session reaper. Configure the connection through `seizu.temporal.*` and allowlist code-defined activity types with `seizu.temporal.enabledWorkflows`.

The CVE dependency remediation workflow additionally needs `secrets.data.remediationGithubToken`, a sandbox provider (`secrets.data.sandboxApiKey` for E2B, or `seizu.sandbox.domain` for self-hosted), and a coding-agent credential (`seizu.sandbox.agent.apiKeyCommand` recommended, or `secrets.data.sandboxAgentApiKey`); tune it via `seizu.remediation.*`.

## Configurable workflows

Workflows are the scheduling and automation interface. Configure activity modules and execution limits through `seizu.workflows.*`. Use `extraEnv`, `extraEnvFrom`, and `secrets.extraData` to provide cloud credentials, Slack tokens, or other action-module secrets.

## External MCP proxies

`seizu.mcp.external.proxies` is serialized verbatim into `MCP_EXTERNAL_PROXIES`, so its entries use the upstream snake_case field names and unknown keys are rejected at startup. A proxy's credential is named by `token_env` rather than embedded in the JSON — supply that variable through `secrets.extraData` or `extraEnvFrom`:

```yaml
seizu:
  mcp:
    external:
      enabled: true
      proxies:
        - name: github
          url: http://mcp-proxy.default.svc.cluster.local:8080/mcp/github
          transport: streamable_http
          auth_mode: bearer
          token_env: MCP_EXTERNAL_PROXY_TOKEN
secrets:
  extraData:
    MCP_EXTERNAL_PROXY_TOKEN: <token>
```

## Tracing

`seizu.telemetry.otlpEndpoint` turns on OTLP spans covering the turn, its dispatch batches, each plan step and every model call — the one view spanning the web service, the turn activity and the step activities it fans out to. Collector credentials go in `secrets.data.telemetryOtlpHeaders`. `seizu.telemetry.recordContent` is off by default: a trace of this system contains graph rows and the user's own words.

## Cartography sync worker

Scheduled Cartography syncs require both the Seizu Temporal orchestration worker and the dedicated credential-bearing activity worker:

```sh
helm upgrade --install seizu ./charts/seizu \
  --set temporalWorker.enabled=true \
  --set cartographyWorker.enabled=true \
  --set-string cartographyWorker.secrets.data.CARTOGRAPHY_NIST_NVD_TOKEN=<key>
```

The dedicated worker defaults to `ghcr.io/mappedsky/seizu-cartography:5.2.0`. It contains Cartography 0.139.0 and the thin Temporal activity worker, and does not receive the main Seizu Secret.

- `seizu.cartography.*` configures the task queue, module allowlist, module timeout/wait, and retry count used by the web and Temporal workers.
- `cartographyWorker.neo4jUri` defaults to `seizu.neo4j.uri`. Neo4j credentials belong in `cartographyWorker.secrets.data.CARTOGRAPHY_NEO4J_USER` and `CARTOGRAPHY_NEO4J_PASSWORD`.
- `cartographyWorker.config` lists supported non-secret worker variables using their exact environment names, including SDK profiles/paths, StatsD, `LOG_LEVEL`, and `CARTOGRAPHY_BIN`. File-valued options can be mounted at the fixed image paths with `cartographyWorker.extraVolumes` and `extraVolumeMounts`.
- `cartographyWorker.secrets.data` lists every Cartography 0.139.0 credential variable Seizu accepts. For an externally managed Secret, set `cartographyWorker.secrets.create=false` and `cartographyWorker.secrets.existingSecret`; its keys must use the listed `CARTOGRAPHY_*` names.
- `seizu.cartography.enabledModules` is empty by default, allowing all registered modules. Set it to a reviewed list to enforce the same allowlist in the UI, dispatcher, and credential-bearing worker.

The registry supports all Cartography 0.139.0 intelligence modules: `airbyte`, `aibom`, `anthropic`, `aws`, `azure`, `bigfix`, `circleci`, `cloudflare`, `crowdstrike`, `cve`, `cve_metadata`, `databricks`, `digitalocean`, `docker_scout`, `duo`, `gcp`, `github`, `gitlab`, `googleworkspace`, `gsuite`, `jamf`, `jumpcloud`, `kandji`, `keycloak`, `kubernetes`, `lastpass`, `microsoft`, `oci`, `okta`, `ontology`, `openai`, `pagerduty`, `salesforce`, `scaleway`, `semgrep`, `sentry`, `sentinelone`, `slack`, `snipeit`, `socketdev`, `spacelift`, `subimage`, `syft`, `tailscale`, `tenable`, `trivy`, `ubuntu`, `vercel`, `workday`, and `workos`, plus `create-indexes` and `analysis`.

## Sandbox delegation

`seizu.sandbox.enabled=true` enables the `sandbox__delegate` chat tool for isolated code execution. Sandboxes are network-isolated by default (`seizu.sandbox.allowInternet=false`).

`seizu.sandbox.sessionPersist` (on by default) suspends a thread's sandbox between turns — keeping full VM state, memory included — so a follow-up turn reads files earlier turns wrote. Set `seizu.deploymentId` whenever the sandbox credentials are shared with another Seizu installation: it is the only ownership claim the reaper acts on.
