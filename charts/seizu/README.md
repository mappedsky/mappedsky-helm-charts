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
