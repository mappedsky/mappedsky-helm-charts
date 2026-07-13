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

The scheduled-query worker is disabled by default. Enable it with:

```sh
helm upgrade --install seizu ./charts/seizu \
  --set scheduledQueries.enabled=true
```

Use `extraEnv`, `extraEnvFrom`, and `secrets` to provide cloud credentials, Slack tokens, or report-store secrets.

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

The `temporal` scheduled-query action hands query results to durable Temporal workflows (e.g. `cve_repo_report`, `cve_dependency_remediation`) executed by a dedicated worker. This chart does not deploy a Temporal server; point `seizu.temporal.address` at one, then set `temporalWorker.enabled=true` to deploy the worker (`python -m reporting.temporal_worker`). Use `seizu.temporal.enabledWorkflows` to allowlist which workflows the action may start.

The CVE dependency remediation workflow additionally needs `secrets.data.remediationGithubToken`, a sandbox provider (`secrets.data.sandboxApiKey` for E2B, or `seizu.sandbox.domain` for self-hosted), and a coding-agent credential (`seizu.sandbox.agent.apiKeyCommand` recommended, or `secrets.data.sandboxAgentApiKey`); tune it via `seizu.remediation.*`.

## Sandbox delegation

`seizu.sandbox.enabled=true` enables the `sandbox__delegate` chat tool for isolated code execution. Sandboxes are network-isolated by default (`seizu.sandbox.allowInternet=false`).
