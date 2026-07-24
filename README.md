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

Charts are published as OCI artifacts to GitHub Container Registry under
`oci://ghcr.io/mappedsky/charts`. Install Seizu directly from the registry:

```sh
helm install seizu oci://ghcr.io/mappedsky/charts/seizu \
  --version 0.3.2 \
  --set seizu.neo4j.uri=bolt://neo4j.default.svc.cluster.local:7687
```

Or install from this repository checkout:

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

## Releasing

Charts publish to `oci://ghcr.io/mappedsky/charts` two ways:

- **On merge to `main`:** any chart whose `Chart.yaml` `version` is not already
  in the registry is packaged and pushed automatically.
- **On a release tag:** push a tag named `<chart>-v<version>` (e.g.
  `seizu-v0.1.0`). The workflow verifies the tag version matches the chart's
  `Chart.yaml` version, then publishes that chart.

```sh
git tag seizu-v0.1.0
git push origin seizu-v0.1.0
```

Already-published versions are skipped, so both paths are safe to re-run.
