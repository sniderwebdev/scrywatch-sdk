# ScryWatch — Kubernetes Deployment

Deploy the OpenTelemetry Collector as a DaemonSet to collect container logs and forward OTLP traces to ScryWatch.

## Prerequisites

- `kubectl` and (optionally) `helm` installed
- ScryWatch API key in a Kubernetes Secret

## Two deployment paths

### Helm (recommended)

Uses the [open-telemetry/opentelemetry-collector](https://github.com/open-telemetry/opentelemetry-helm-charts) chart.

See [`/kubernetes/helm/README.md`](/kubernetes/helm/README.md) for install commands.

### Raw YAML

Plain Kubernetes manifests for environments without Helm.

See [`/kubernetes/raw-yaml/README.md`](/kubernetes/raw-yaml/README.md) for apply order and instructions.

## What the collector does

| Capability | Status |
|-----------|--------|
| Collect container logs from `/var/log/pods` | ✅ Yes |
| Forward logs to ScryWatch | ❌ Not yet — use the SDK directly |
| Forward OTLP traces to ScryWatch | ✅ Yes |
