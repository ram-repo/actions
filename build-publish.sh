#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# daap-build-publish/scripts/build-publish.sh
#
# Drives the inner loop of the daap-build-publish composite action.
# Called once per workflow run; iterates over every resolved product path.
#
# Environment variables (set by action.yml via the `env:` block):
#   DATA_PRODUCT_PATHS      — raw multiline input from the caller
#   DATA_ASSETS_PATH        — relative path to the data-assets root
#   BASE_SHA                — base commit SHA for change detection (may be empty)
#   HEAD_SHA                — head commit SHA for change detection (may be empty)
#   SKIP_VERSION_CHECK      — "true" | "false"
#   ALLOW_OVERWRITE         — "true" | "false"
#   ARTIFACTORY_USERNAME    — Artifactory credential
#   ARTIFACTORY_PASSWORD    — Artifactory credential
#   ARTIFACTORY_PACKAGE_URL — target repository URL (production or snapshot)
#   DOCKER_REGISTRY         — Docker registry hosting the DAAP CLI image
#   GITHUB_TOKEN            — used for PR comment posting
#   PR_NUMBER               — GitHub PR number (for comment posting)
#   REPO_OWNER / REPO_NAME  — used for PR comment posting
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DAAP_IMAGE="${DOCKER_REGISTRY}/data-fabric-docker/daap-cli:latest"

# ── Output accumulators ──────────────────────────────────────────────────────
PUBLISHED_PACKAGES=()
PACKAGE_IDS=()
VERSIONS=()

# ── Helper: strip leading "- " from YAML list entries ───────────────────────
strip_yaml_prefix() {
  sed 's/^[[:space:]]*-[[:space:]]*//'
}

# ── Helper: post a PR comment when version bump is missing ──────────────────
post_pr_comment() {
  local path="$1"
  echo "::warning::Posting PR comment — version bump required at ${path}"

  if [[ -z "${PR_NUMBER:-}" ]]; then
    echo "::warning::No PR number available; skipping comment post."
    return
  fi

  curl -s -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/issues/${PR_NUMBER}/comments" \
    -d @- <<JSON
{
  "body": "**Version bump required**\n\nPackage at \`${path}\` has changes but no \`version:\` bump in \`manifest.yaml\`.\n\nPlease update the \`version:\` field before merging."
}
JSON
}

# ── Step 1: resolve product paths ───────────────────────────────────────────
# Accepts the raw multiline DATA_PRODUCT_PATHS input and produces an array
# of resolved absolute product root paths.

RESOLVED_PATHS=()

while IFS= read -r raw_line; do
  # Skip blank lines and comment lines
  [[ -z "$raw_line" ]] && continue
  [[ "$raw_line" =~ ^[[:space:]]*# ]] && continue

  # Strip leading YAML list prefix ("- ")
  line=$(echo "$raw_line" | strip_yaml_prefix | xargs)
  [[ -z "$line" ]] && continue

  if [[ -f "${line}/manifest.yaml" ]]; then
    # ── Explicit mode: path has manifest.yaml at root ──────────────────────
    echo "::debug::Explicit product path: ${line}"
    RESOLVED_PATHS+=("$line")
  else
    # ── Mono-repo mode: scan immediate subdirectories ──────────────────────
    echo "::debug::Scanning subdirectories of: ${line}"
    if [[ ! -d "$line" ]]; then
      echo "::error::data-product-paths entry '${line}' is not a directory and has no manifest.yaml."
      exit 1
    fi

    while IFS= read -r -d '' subdir; do
      if [[ -f "${subdir}/manifest.yaml" ]]; then
        RESOLVED_PATHS+=("$subdir")
        echo "::debug::  Found product at: ${subdir}"
      else
        echo "::notice::  Skipping ${subdir} (no manifest.yaml)"
      fi
    done < <(find "$line" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
  fi
done <<< "$DATA_PRODUCT_PATHS"

if [[ ${#RESOLVED_PATHS[@]} -eq 0 ]]; then
  echo "::warning::No product paths resolved from data-product-paths input. Nothing to build."
  exit 0
fi

echo "Resolved ${#RESOLVED_PATHS[@]} product path(s):"
printf '  %s\n' "${RESOLVED_PATHS[@]}"

# ── Step 2: process each resolved product path ───────────────────────────────

for CURRENT_PATH in "${RESOLVED_PATHS[@]}"; do
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Processing: ${CURRENT_PATH}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # ── 2a. Change detection ─────────────────────────────────────────────────
  if [[ -n "${BASE_SHA}" && -n "${HEAD_SHA}" ]]; then
    CHANGES=$(git diff --name-only "${BASE_SHA}" "${HEAD_SHA}" -- "${CURRENT_PATH}" 2>/dev/null || true)
    if [[ -z "$CHANGES" ]]; then
      echo "::notice::No changes detected in ${CURRENT_PATH} — skipping."
      continue
    fi
    echo "Changed files detected:"
    echo "$CHANGES" | sed 's/^/  /'
  else
    echo "base-sha/head-sha not set — skipping change detection for ${CURRENT_PATH}."
  fi

  # ── 2b. Read manifest.yaml ───────────────────────────────────────────────
  MANIFEST="${CURRENT_PATH}/manifest.yaml"
  if [[ ! -f "$MANIFEST" ]]; then
    echo "::error::manifest.yaml not found at ${MANIFEST}"
    exit 1
  fi

  PACKAGE_ID=$(grep -E '^package_id:' "$MANIFEST" | head -1 | awk '{print $2}' | tr -d '"'"'" | xargs)
  VERSION=$(grep -E '^version:' "$MANIFEST" | head -1 | awk '{print $2}' | tr -d '"'"'" | xargs)

  if [[ -z "$PACKAGE_ID" ]]; then
    echo "::error::Could not extract package_id from ${MANIFEST}"
    exit 1
  fi
  if [[ -z "$VERSION" ]]; then
    echo "::error::Could not extract version from ${MANIFEST}"
    exit 1
  fi

  echo "package_id : ${PACKAGE_ID}"
  echo "version    : ${VERSION}"

  # ── 2c. Version bump check (open PRs only) ───────────────────────────────
  if [[ "${SKIP_VERSION_CHECK}" != "true" ]]; then
    if [[ -z "${BASE_SHA}" || -z "${HEAD_SHA}" ]]; then
      echo "::error::skip-version-check is false but base-sha/head-sha are not set."
      exit 1
    fi

    VERSION_BUMP=$(git diff "${BASE_SHA}" "${HEAD_SHA}" \
      -- "${CURRENT_PATH}/manifest.yaml" \
      | grep "^+version:" || true)

    if [[ -z "$VERSION_BUMP" ]]; then
      echo "::error::Version bump required at ${CURRENT_PATH} — no 'version:' change found in manifest.yaml diff."
      post_pr_comment "$CURRENT_PATH"
      exit 1
    fi

    echo "Version bump confirmed: ${VERSION_BUMP}"
  else
    echo "skip-version-check=true — version bump check skipped."
  fi

  # ── 2d. Build ─────────────────────────────────────────────────────────────
  echo "Building package: ${PACKAGE_ID} @ ${VERSION}"

  docker run --rm \
    -v "${GITHUB_WORKSPACE}:/workspace" \
    -w /workspace \
    -e ARTIFACTORY_USERNAME \
    -e ARTIFACTORY_PASSWORD \
    -e ARTIFACTORY_PACKAGE_URL \
    "${DAAP_IMAGE}" \
    daap package build --path "${CURRENT_PATH}"

  # ── 2e. Locate the zip produced by the build ─────────────────────────────
  ZIP_NAME="${PACKAGE_ID}-${VERSION}.zip"
  ZIP_PATH=$(find "${GITHUB_WORKSPACE}" -maxdepth 2 -name "${ZIP_NAME}" | head -1)

  if [[ -z "$ZIP_PATH" ]]; then
    echo "::error::Expected zip not found after build: ${ZIP_NAME}"
    exit 1
  fi

  echo "Located zip: ${ZIP_PATH}"

  # ── 2f. Publish ───────────────────────────────────────────────────────────
  FORCE_FLAG=""
  if [[ "${ALLOW_OVERWRITE}" == "true" ]]; then
    FORCE_FLAG="--force"
    echo "allow-overwrite=true — publishing with --force"
  fi

  echo "Publishing ${ZIP_NAME} → ${ARTIFACTORY_PACKAGE_URL}"

  docker run --rm \
    -v "${GITHUB_WORKSPACE}:/workspace" \
    -w /workspace \
    -e ARTIFACTORY_USERNAME \
    -e ARTIFACTORY_PASSWORD \
    -e ARTIFACTORY_PACKAGE_URL \
    -e DAAP_DATA_ASSETS_PATH="${DATA_ASSETS_PATH}" \
    "${DAAP_IMAGE}" \
    daap package publish --path "${ZIP_PATH}" ${FORCE_FLAG}

  echo "✓ Published: ${PACKAGE_ID} @ ${VERSION}"

  # ── 2g. Accumulate outputs ────────────────────────────────────────────────
  PUBLISHED_PACKAGES+=("${PACKAGE_ID}")
  PACKAGE_IDS+=("${PACKAGE_ID}")
  VERSIONS+=("${VERSION}")
done

# ── Step 3: write output files ───────────────────────────────────────────────
if [[ ${#PUBLISHED_PACKAGES[@]} -gt 0 ]]; then
  printf '%s\n' "${PUBLISHED_PACKAGES[@]}" > /tmp/daap-published-packages.txt
  printf '%s\n' "${PACKAGE_IDS[@]}"        > /tmp/daap-package-ids.txt
  printf '%s\n' "${VERSIONS[@]}"           > /tmp/daap-versions.txt

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Published packages:"
  printf '  %s\n' "${PUBLISHED_PACKAGES[@]}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
  echo "::notice::No packages were published in this run (all paths skipped or no changes)."
fi
