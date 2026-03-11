# ScryWatch — Raw YAML Deployment

Deploy the OpenTelemetry Collector as a DaemonSet using plain Kubernetes manifests.

## Prerequisites

- `kubectl` installed and configured
- ScryWatch API key

## Apply order

Apply manifests in this order (namespace must exist before the Secret):

```bash
# 1. Create the namespace
kubectl create namespace observability

# 2. Create the credentials Secret (edit the file first — replace placeholder values)
#    OR use kubectl directly (recommended):
kubectl create secret generic scrywatch-credentials \
  --from-literal=SCRYWATCH_API_KEY=<your-key> \
  --from-literal=SCRYWATCH_ENDPOINT=https://api.scrywatch.com \
  --namespace observability

# 3. Apply the ConfigMap
kubectl apply -f collector-configmap.yaml

# 4. Apply the DaemonSet
kubectl apply -f collector-daemonset.yaml
```

> **Note:** If you edit `scrywatch-secret.yaml` directly, replace both placeholder values before applying. The `kubectl create secret generic` approach above is safer.

## Helm alternative

See [`../helm/`](../helm/) for Helm values that achieve the same result with fewer manual steps.
