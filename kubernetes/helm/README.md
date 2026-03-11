# ScryWatch — Helm Deployment

Deploy the OpenTelemetry Collector as a DaemonSet using the [open-telemetry/opentelemetry-collector](https://github.com/open-telemetry/opentelemetry-helm-charts) Helm chart.

## Prerequisites

- `kubectl` and `helm` installed
- ScryWatch API key

## Logs only (no trace forwarding)

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
helm install otel-collector open-telemetry/opentelemetry-collector \
  --namespace observability --create-namespace \
  -f values-logs-only.yaml
```

> **Note:** ScryWatch does not yet support OTLP log ingest. Use the ScryWatch SDK directly for log shipping. This config demonstrates log collection only.

## Logs + traces (traces forwarded to ScryWatch)

```bash
# 1. Create the credentials secret
kubectl create secret generic scrywatch-credentials \
  --from-literal=SCRYWATCH_API_KEY=<your-key> \
  --from-literal=SCRYWATCH_ENDPOINT=https://api.scrywatch.com \
  --namespace observability --create-namespace

# 2. Install the collector
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
helm install otel-collector open-telemetry/opentelemetry-collector \
  --namespace observability --create-namespace \
  -f values-logs-and-traces.yaml
```

## Raw YAML alternative

See [`../raw-yaml/`](../raw-yaml/) for plain Kubernetes manifests without Helm.
