#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# daap-deploy/scripts/deploy.sh
#
# Generates a Kubernetes Job manifest at runtime and applies it.
# Called once per workflow run by the daap-deploy composite action.
#
# Environment variables (set by action.yml via the `env:` block):
#   PACKAGES              — raw multiline packages input
#   KUBE_CONFIG           — base64-encoded kubeconfig
#   METHOD                — Overwrite | Upgrade (default: Overwrite)
#   RETRY_LIMIT           — Job backoffLimit (default: 0)
#   NAMESPACE             — target Kubernetes namespace
#   JOB_TIMEOUT           — seconds to wait for Job completion (default: 600)
#   DAAP_CUSTOM_COMMANDS  — raw multiline custom-commands input
#   EXTRA_ENV             — KEY=VALUE pairs, one per line
#   EXTRA_SECRET_REFS     — space-separated Secret names
#   EXTRA_CONFIGMAP_REFS  — space-separated ConfigMap names
#   DOCKER_REGISTRY       — Docker registry for utility images
#   GITHUB_RUN_ID         — used to generate a unique Job name
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Write and activate kubeconfig ────────────────────────────────────────────
echo "${KUBE_CONFIG}" | base64 -d > /tmp/kubeconfig
export KUBECONFIG=/tmp/kubeconfig

# ── Derived values ───────────────────────────────────────────────────────────
JOB_NAME="daap-deploy-${GITHUB_RUN_ID}"
DAAP_IMAGE="${DOCKER_REGISTRY}/data-fabric-docker/daap-cli:latest"
DOCKERIZE_IMAGE="${DOCKER_REGISTRY}/virtual-docker/jwilder/dockerize:v0.9.1"
METHOD="${METHOD:-Overwrite}"
RETRY_LIMIT="${RETRY_LIMIT:-0}"
NAMESPACE="${NAMESPACE:-default}"
JOB_TIMEOUT="${JOB_TIMEOUT:-600}"

echo "Job name  : ${JOB_NAME}"
echo "Namespace : ${NAMESPACE}"
echo "Method    : ${METHOD}"
echo "Retry     : ${RETRY_LIMIT}"

# ── Strip leading YAML list prefix from multiline inputs ────────────────────
strip_yaml_prefix() {
  sed 's/^[[:space:]]*-[[:space:]]*//'
}

# Normalise PACKAGES (strip "- " prefix; blank lines removed)
PACKAGES_CLEAN=$(echo "${PACKAGES}" | strip_yaml_prefix | grep -v '^[[:space:]]*$' || true)

echo "Packages to deploy:"
echo "${PACKAGES_CLEAN}" | sed 's/^/  /'

# ── Build the container script (package loop + custom commands) ──────────────
DEPLOY_SCRIPT=""

# Package deploy loop
if [[ -n "$PACKAGES_CLEAN" ]]; then
  DEPLOY_SCRIPT+='echo "=== Starting package deployments ===" '
  DEPLOY_SCRIPT+='; '
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    DEPLOY_SCRIPT+="echo \"Deploying: ${pkg}\" "
    DEPLOY_SCRIPT+="; daap package deploy \"${pkg}\" --method \"\${DAAP_DEPLOY_METHOD}\" "
    DEPLOY_SCRIPT+="; echo \"✓ Deployed: ${pkg}\" ; "
  done <<< "$PACKAGES_CLEAN"
fi

# Custom commands (appended after package loop)
if [[ -n "${DAAP_CUSTOM_COMMANDS:-}" ]]; then
  DEPLOY_SCRIPT+='echo "=== Running custom commands ===" ; '
  while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    DEPLOY_SCRIPT+="echo \"+ ${cmd}\" ; ${cmd} ; "
  done <<< "${DAAP_CUSTOM_COMMANDS}"
fi

DEPLOY_SCRIPT+='echo "=== All steps completed successfully ==="'

# ── Build extra-env YAML block ───────────────────────────────────────────────
EXTRA_ENV_YAML=""
if [[ -n "${EXTRA_ENV:-}" ]]; then
  while IFS= read -r kv; do
    [[ -z "$kv" ]] && continue
    KEY="${kv%%=*}"
    VAL="${kv#*=}"
    EXTRA_ENV_YAML+="            - name: ${KEY}"$'\n'
    EXTRA_ENV_YAML+="              value: \"${VAL}\""$'\n'
  done <<< "${EXTRA_ENV}"
fi

# ── Build envFrom block ──────────────────────────────────────────────────────
ENV_FROM_YAML=""
if [[ -n "${EXTRA_SECRET_REFS:-}" || -n "${EXTRA_CONFIGMAP_REFS:-}" ]]; then
  ENV_FROM_YAML="          envFrom:"$'\n'
  for secret in ${EXTRA_SECRET_REFS:-}; do
    ENV_FROM_YAML+="            - secretRef:"$'\n'
    ENV_FROM_YAML+="                name: ${secret}"$'\n'
  done
  for cm in ${EXTRA_CONFIGMAP_REFS:-}; do
    ENV_FROM_YAML+="            - configMapRef:"$'\n'
    ENV_FROM_YAML+="                name: ${cm}"$'\n'
  done
fi

# ── Render the Job manifest ──────────────────────────────────────────────────
cat > /tmp/daap-job.yaml <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/managed-by: daap-deploy-action
    github-run-id: "${GITHUB_RUN_ID}"
spec:
  backoffLimit: ${RETRY_LIMIT}
  template:
    metadata:
      labels:
        sidecar.istio.io/inject: "false"
        app.kubernetes.io/name: daap-deploy
        github-run-id: "${GITHUB_RUN_ID}"
    spec:
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        fsGroup: 65532
      initContainers:
        - name: wait-for-services
          image: ${DOCKERIZE_IMAGE}
          imagePullPolicy: IfNotPresent
          command:
            - "dockerize"
            - "-wait"
            - "tcp://datahub-gms:8080"
            - "-wait"
            - "tcp://datahub-frontend:9002"
            - "-wait"
            - "tcp://anybase:5000"
            - "-timeout"
            - "180s"
      containers:
        - name: daap-cli
          image: ${DAAP_IMAGE}
          imagePullPolicy: Always
          securityContext:
            capabilities:
              drop: [ALL]
            readOnlyRootFilesystem: false
            runAsNonRoot: true
            runAsUser: 65532
          command: ["/bin/bash", "-c"]
          args:
            - |
              set -euo pipefail
              ${DEPLOY_SCRIPT}
          env:
            # ── Standard baseline (pre-configured in cluster) ──────────────
            - name: DATAHUB_TELEMETRY_ENABLED
              value: "false"
            - name: DISCOVER_ADMIN_USERNAME
              valueFrom:
                secretKeyRef:
                  name: discover-admin-user-password
                  key: username
            - name: DISCOVER_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: discover-admin-user-password
                  key: password
            - name: DISCOVER_API_USERNAME
              valueFrom:
                secretKeyRef:
                  name: discover-api-user-password
                  key: username
            - name: DISCOVER_API_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: discover-api-user-password
                  key: password
            - name: EXPLORE_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: explore-admin-user-password
                  key: password
            - name: ARTIFACTORY_USERNAME
              valueFrom:
                secretKeyRef:
                  name: artifactory-credentials
                  key: username
                  optional: true
            - name: ARTIFACTORY_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: artifactory-credentials
                  key: password
                  optional: true
            # ── Injected by the action at runtime ─────────────────────────
            - name: DAAP_DEPLOY_METHOD
              value: "${METHOD}"
${EXTRA_ENV_YAML}
${ENV_FROM_YAML}
EOF

echo "Generated Job manifest:"
echo "────────────────────────────────────────"
cat /tmp/daap-job.yaml
echo "────────────────────────────────────────"

# ── Apply the Job ────────────────────────────────────────────────────────────
echo "Applying Job to namespace '${NAMESPACE}'..."
kubectl apply -f /tmp/daap-job.yaml

echo "Waiting for Job completion (timeout: ${JOB_TIMEOUT}s)..."

# Wait for success or failure
if kubectl wait \
    --for=condition=complete \
    "job/${JOB_NAME}" \
    --timeout="${JOB_TIMEOUT}s" \
    --namespace="${NAMESPACE}" 2>/dev/null; then

  echo "::notice::Job ${JOB_NAME} completed successfully."
  echo "job-name=${JOB_NAME}" >> "$GITHUB_OUTPUT"
  echo "status=Succeeded"     >> "$GITHUB_OUTPUT"
else
  # Check whether it actually failed (vs just timed out)
  kubectl wait \
    --for=condition=failed \
    "job/${JOB_NAME}" \
    --timeout="30s" \
    --namespace="${NAMESPACE}" 2>/dev/null || true

  echo "::error::Job ${JOB_NAME} failed or timed out."

  echo "Job description:"
  kubectl describe "job/${JOB_NAME}" --namespace="${NAMESPACE}" || true

  echo "Pod logs:"
  kubectl logs \
    -l "github-run-id=${GITHUB_RUN_ID}" \
    --namespace="${NAMESPACE}" \
    --tail=100 \
    --prefix \
    2>/dev/null || echo "(no logs available)"

  echo "job-name=${JOB_NAME}" >> "$GITHUB_OUTPUT"
  echo "status=Failed"        >> "$GITHUB_OUTPUT"

  exit 1
fi
