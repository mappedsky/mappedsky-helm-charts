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
  --version 0.4.0 \
  --set seizu.neo4j.uri=bolt://neo4j.default.svc.cluster.local:7687 \
  --set seizu.reportStore.sqlDatabaseUrl=postgresql://postgres.default.svc.cluster.local:5432/seizu
```

Or install from this repository checkout:

```sh
helm install seizu ./charts/seizu \
  --set seizu.neo4j.uri=bolt://neo4j.default.svc.cluster.local:7687 \
  --set seizu.reportStore.sqlDatabaseUrl=postgresql://postgres.default.svc.cluster.local:5432/seizu
```

Seizu expects these external dependencies:

- A reachable Neo4j instance. The chart does not deploy Neo4j.
- PostgreSQL. Seizu 5 keeps every application record there and has no other backend; set `seizu.reportStore.sqlDatabaseUrl` and supply credentials through `secrets.data.sqlDatabaseUser` / `secrets.data.sqlDatabasePassword`. Chat additionally wants its own LangGraph checkpoint database (`seizu.chat.checkpoint.databaseUrl`).
- A Temporal server, for anything beyond a read-only web deployment. Chat turns, scheduled chats and configurable workflows all execute as Temporal workflows. The chart does not deploy Temporal; point `seizu.temporal.address` at one and set `temporalWorker.enabled=true`.

See the [chart README](charts/seizu/README.md) for the full configuration surface and the 4.x -> 5.x upgrade notes.

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

Development chart releases use a semantic-version prerelease suffix and must be
installed explicitly. For example, a chart with version `0.4.1-dev.1` is
released with tag `seizu-v0.4.1-dev.1` and installed with:

```sh
helm install seizu oci://ghcr.io/mappedsky/charts/seizu \
  --version 0.4.1-dev.1
```
