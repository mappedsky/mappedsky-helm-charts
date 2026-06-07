# MappedSky Helm Charts

This repository hosts Helm charts for open source projects maintained by MappedSky.

## Repository layout

```text
charts/
  seizu/
    Chart.yaml
    values.yaml
    templates/
```

Add each project chart under `charts/<project-name>`.

## Usage

Install Seizu from this repository checkout:

```sh
helm install seizu ./charts/seizu \
  --set seizu.neo4j.uri=bolt://neo4j.default.svc.cluster.local:7687
```

Seizu expects these external dependencies:

- A reachable Neo4j instance. The chart does not deploy Neo4j by default.
- A report-store backend. By default this is DynamoDB, configured with `seizu.reportStore.dynamodb.tableName`, `seizu.reportStore.dynamodb.region`, and optionally `seizu.reportStore.dynamodb.endpointUrl`. To use SQL instead, set `seizu.reportStore.backend=sqlmodel` and provide `seizu.reportStore.sqlDatabaseUrl`.

## Development

Lint charts locally:

```sh
helm lint charts/seizu
```

Render manifests locally:

```sh
helm template seizu charts/seizu
```
