# ─────────────────────────────────────────────────────────────────────────────
# Shared Action: daap-build-publish
# Repository:   grid-platform/df-actions
# Purpose:      Validates version bumps, builds package zips, and publishes
#               them to Artifactory. Iterates over every path listed in
#               data-product-paths in a single action call.
#
# Supports:
#   - Explicit product path (co-location pattern) — path contains manifest.yaml
#   - Mono-repo parent directory — every immediate subdir scanned automatically
#   - Change detection via base-sha / head-sha
#   - Version bump enforcement on open PRs (skip-version-check: false)
#   - Snapshot vs production routing via artifactory-package-url input
# ─────────────────────────────────────────────────────────────────────────────
name: "DAAP Build & Publish"
description: >
  Validates version bumps, builds package zips, and publishes them to
  Artifactory. Accepts a multiline data-product-paths input to process
  one or more products in a single call.

inputs:
  # ── Required ───────────────────────────────────────────────────────────────
  data-product-paths:
    description: >
      One entry per line. If a path has manifest.yaml at its root it is used
      directly (explicit / co-location mode). If it does not, every immediate
      subdirectory is scanned (mono-repo mode); subdirs without manifest.yaml
      are skipped silently. Both plain and YAML list format (leading "- ")
      are accepted.
    required: true

  data-assets-path:
    description: >
      Root path for all data assets. Assets are resolved at
      <path>/<package_id>/<asset_id>/. Typically "data-assets" at the repo
      root but any relative path is accepted.
    required: true

  artifactory-username:
    description: "Artifactory username"
    required: true

  artifactory-password:
    description: >
      Artifactory password. Also used for Docker registry login to pull the
      DAAP CLI image.
    required: true

  artifactory-package-url:
    description: >
      Full URL to the target Artifactory package repository (production or
      snapshot). The consumer workflow is responsible for routing to the
      correct URL based on trigger type.
    required: true

  # ── Optional — change detection & version check ───────────────────────────
  base-sha:
    description: >
      Base commit SHA for change detection and version bump diff.
      On PR events:         github.event.pull_request.base.sha
      On branch pushes:     HEAD^1 (computed in consumer workflow)
      On tag push:          leave empty — change detection is skipped and all
                            products are published unconditionally.
      On workflow_dispatch with explicit products: leave empty.
    required: false
    default: ""

  head-sha:
    description: >
      Head commit SHA for change detection and version bump diff.
      On PR events:         github.sha
      On branch pushes:     HEAD (computed in consumer workflow)
      Leave empty when base-sha is empty.
    required: false
    default: ""

  skip-version-check:
    description: >
      When true, skips the manifest.yaml version bump check. Set to true for
      all non-PR triggers (post-merge, branch push, tag push, dispatch). The
      version was already validated on the open PR.
    required: false
    default: "false"

  allow-overwrite:
    description: >
      When true, passes --force to "daap package publish", allowing overwrite
      of an existing artifact at the same version in Artifactory. Independent
      of artifactory-package-url — both snapshot and production combinations
      are valid (e.g. allow-overwrite=true + production URL on tag push).
    required: false
    default: "false"

  # ── Optional — Docker registry ────────────────────────────────────────────
  docker-registry:
    description: "Docker registry hosting the DAAP CLI image"
    required: false
    default: "gart.software.power-v.com"

outputs:
  published-packages:
    description: >
      Newline-separated list of all package_id values successfully published.
      Pass directly to daap-deploy's packages input via
      ${{ needs.publish.outputs.published-packages }}.
    value: ${{ steps.collect-outputs.outputs.published-packages }}

  package-ids:
    description: >
      Newline-separated list of package_id values (one per resolved path,
      same order as input).
    value: ${{ steps.collect-outputs.outputs.package-ids }}

  versions:
    description: >
      Newline-separated list of version values (one per resolved path,
      same order as package-ids).
    value: ${{ steps.collect-outputs.outputs.versions }}

runs:
  using: composite
  steps:

    # ── Step 1: Docker login ─────────────────────────────────────────────────
    - name: Docker login
      shell: bash
      run: |
        echo "${{ inputs.artifactory-password }}" | \
          docker login "${{ inputs.docker-registry }}" \
            --username "${{ inputs.artifactory-username }}" \
            --password-stdin

    # ── Step 2: Resolve product paths ────────────────────────────────────────
    # Reads data-product-paths and resolves each entry to concrete product
    # roots, writing them newline-separated to /tmp/daap-resolved-paths.txt.
    # Explicit mode: entry has manifest.yaml at root → used as-is.
    # Mono-repo mode: entry has no manifest.yaml → all immediate subdirs scanned.
    - name: Resolve product paths
      id: resolve-paths
      shell: bash
      env:
        DATA_PRODUCT_PATHS: ${{ inputs.data-product-paths }}
      run: |
        set -euo pipefail
        RESOLVED=()

        while IFS= read -r raw_line; do
          [[ -z "$raw_line" ]] && continue
          [[ "$raw_line" =~ ^[[:space:]]*# ]] && continue

          # Strip leading YAML list prefix ("- ")
          line=$(echo "$raw_line" | sed 's/^[[:space:]]*-[[:space:]]*//' | xargs)
          [[ -z "$line" ]] && continue

          if [[ -f "${line}/manifest.yaml" ]]; then
            # Explicit / co-location mode
            echo "::debug::Explicit product path: ${line}"
            RESOLVED+=("$line")
          else
            # Mono-repo mode — scan immediate subdirectories
            if [[ ! -d "$line" ]]; then
              echo "::error::data-product-paths entry '${line}' is not a directory and has no manifest.yaml."
              exit 1
            fi
            echo "::debug::Scanning subdirectories of: ${line}"
            while IFS= read -r -d '' subdir; do
              if [[ -f "${subdir}/manifest.yaml" ]]; then
                RESOLVED+=("$subdir")
                echo "::debug::  Found product at: ${subdir}"
              else
                echo "::notice::  Skipping ${subdir} — no manifest.yaml"
              fi
            done < <(find "$line" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
          fi
        done <<< "$DATA_PRODUCT_PATHS"

        if [[ ${#RESOLVED[@]} -eq 0 ]]; then
          echo "::warning::No product paths resolved from data-product-paths. Nothing to build."
          # Write empty file so downstream steps handle the empty-list case gracefully
          touch /tmp/daap-resolved-paths.txt
        else
          echo "Resolved ${#RESOLVED[@]} product path(s):"
          printf '  %s\n' "${RESOLVED[@]}"
          printf '%s\n' "${RESOLVED[@]}" > /tmp/daap-resolved-paths.txt
        fi

    # ── Step 3: Change detection ─────────────────────────────────────────────
    # For each resolved path, check whether any files changed between
    # base-sha and head-sha. Paths with no changes are removed from the list.
    # When base-sha is empty change detection is skipped entirely (tag push /
    # explicit workflow_dispatch).
    - name: Change detection
      id: change-detection
      shell: bash
      env:
        BASE_SHA: ${{ inputs.base-sha }}
        HEAD_SHA: ${{ inputs.head-sha }}
      run: |
        set -euo pipefail

        if [[ ! -s /tmp/daap-resolved-paths.txt ]]; then
          echo "No resolved paths — skipping change detection."
          touch /tmp/daap-changed-paths.txt
          exit 0
        fi

        if [[ -z "${BASE_SHA}" || -z "${HEAD_SHA}" ]]; then
          echo "base-sha / head-sha not set — skipping change detection; all resolved paths will be processed."
          cp /tmp/daap-resolved-paths.txt /tmp/daap-changed-paths.txt
          exit 0
        fi

        CHANGED=()
        while IFS= read -r path; do
          [[ -z "$path" ]] && continue
          FILES=$(git diff --name-only "${BASE_SHA}" "${HEAD_SHA}" -- "${path}" 2>/dev/null || true)
          if [[ -z "$FILES" ]]; then
            echo "::notice::No changes in ${path} — skipping."
          else
            echo "Changes detected in ${path}:"
            echo "$FILES" | sed 's/^/  /'
            CHANGED+=("$path")
          fi
        done < /tmp/daap-resolved-paths.txt

        if [[ ${#CHANGED[@]} -eq 0 ]]; then
          echo "::notice::No changed products detected — nothing to build."
          touch /tmp/daap-changed-paths.txt
        else
          printf '%s\n' "${CHANGED[@]}" > /tmp/daap-changed-paths.txt
        fi

    # ── Step 4: Version bump check ───────────────────────────────────────────
    # Runs only when skip-version-check is false (i.e. on open PRs).
    # Fails immediately and posts a PR comment for any product whose
    # manifest.yaml does not have a bumped version: line in the diff.
    - name: Version bump check
      id: version-check
      shell: bash
      env:
        SKIP_VERSION_CHECK: ${{ inputs.skip-version-check }}
        BASE_SHA:           ${{ inputs.base-sha }}
        HEAD_SHA:           ${{ inputs.head-sha }}
        GITHUB_TOKEN:       ${{ github.token }}
        PR_NUMBER:          ${{ github.event.pull_request.number }}
        REPO_OWNER:         ${{ github.repository_owner }}
        REPO_NAME:          ${{ github.event.repository.name }}
      run: |
        set -euo pipefail

        if [[ "${SKIP_VERSION_CHECK}" == "true" ]]; then
          echo "skip-version-check=true — version bump check skipped."
          exit 0
        fi

        if [[ ! -s /tmp/daap-changed-paths.txt ]]; then
          echo "No changed paths — version bump check not needed."
          exit 0
        fi

        if [[ -z "${BASE_SHA}" || -z "${HEAD_SHA}" ]]; then
          echo "::error::skip-version-check is false but base-sha / head-sha are not set."
          exit 1
        fi

        FAILED=0
        while IFS= read -r path; do
          [[ -z "$path" ]] && continue

          VERSION_BUMP=$(git diff "${BASE_SHA}" "${HEAD_SHA}" \
            -- "${path}/manifest.yaml" \
            | grep "^+version:" || true)

          if [[ -z "$VERSION_BUMP" ]]; then
            echo "::error::Version bump required at ${path} — no 'version:' change found in manifest.yaml diff."

            # Post PR comment if we have a PR number
            if [[ -n "${PR_NUMBER:-}" ]]; then
              curl -s -X POST \
                -H "Authorization: Bearer ${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github+json" \
                "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/issues/${PR_NUMBER}/comments" \
                -d "{\"body\":\"**Version bump required**\n\nPackage at \`${path}\` has changes but no \`version:\` bump in \`manifest.yaml\`.\n\nPlease update the \`version:\` field before merging.\"}"
            fi

            FAILED=1
          else
            echo "Version bump confirmed at ${path}: ${VERSION_BUMP}"
          fi
        done < /tmp/daap-changed-paths.txt

        if [[ "$FAILED" -eq 1 ]]; then
          exit 1
        fi

    # ── Step 5: Build & publish loop ─────────────────────────────────────────
    # For each changed path: read manifest, docker build, locate zip,
    # docker publish (with --force when allow-overwrite=true).
    - name: Build and publish packages
      id: build-publish
      shell: bash
      env:
        ARTIFACTORY_USERNAME:    ${{ inputs.artifactory-username }}
        ARTIFACTORY_PASSWORD:    ${{ inputs.artifactory-password }}
        ARTIFACTORY_PACKAGE_URL: ${{ inputs.artifactory-package-url }}
        DATA_ASSETS_PATH:        ${{ inputs.data-assets-path }}
        ALLOW_OVERWRITE:         ${{ inputs.allow-overwrite }}
        DOCKER_REGISTRY:         ${{ inputs.docker-registry }}
      run: |
        set -euo pipefail

        DAAP_IMAGE="${DOCKER_REGISTRY}/data-fabric-docker/daap-cli:latest"
        PUBLISHED_PACKAGES=()
        PACKAGE_IDS=()
        VERSIONS=()

        if [[ ! -s /tmp/daap-changed-paths.txt ]]; then
          echo "::notice::No packages to build — all paths were skipped or had no changes."
          touch /tmp/daap-published-packages.txt
          touch /tmp/daap-package-ids.txt
          touch /tmp/daap-versions.txt
          exit 0
        fi

        while IFS= read -r CURRENT_PATH; do
          [[ -z "$CURRENT_PATH" ]] && continue

          echo ""
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "Processing: ${CURRENT_PATH}"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

          # Read manifest
          MANIFEST="${CURRENT_PATH}/manifest.yaml"
          if [[ ! -f "$MANIFEST" ]]; then
            echo "::error::manifest.yaml not found at ${MANIFEST}"
            exit 1
          fi

          PACKAGE_ID=$(grep -E '^package_id:' "$MANIFEST" | head -1 | awk '{print $2}' | tr -d "\"'" | xargs)
          VERSION=$(grep    -E '^version:'    "$MANIFEST" | head -1 | awk '{print $2}' | tr -d "\"'" | xargs)

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

          # Build
          echo "Building package: ${PACKAGE_ID} @ ${VERSION}"
          docker run --rm \
            -v "${GITHUB_WORKSPACE}:/workspace" \
            -w /workspace \
            -e ARTIFACTORY_USERNAME \
            -e ARTIFACTORY_PASSWORD \
            -e ARTIFACTORY_PACKAGE_URL \
            "${DAAP_IMAGE}" \
            daap package build --path "${CURRENT_PATH}"

          # Locate zip
          ZIP_NAME="${PACKAGE_ID}-${VERSION}.zip"
          ZIP_PATH=$(find "${GITHUB_WORKSPACE}" -maxdepth 2 -name "${ZIP_NAME}" | head -1)
          if [[ -z "$ZIP_PATH" ]]; then
            echo "::error::Expected zip not found after build: ${ZIP_NAME}"
            exit 1
          fi
          echo "Located zip: ${ZIP_PATH}"

          # Publish (--force when allow-overwrite=true)
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

          PUBLISHED_PACKAGES+=("${PACKAGE_ID}")
          PACKAGE_IDS+=("${PACKAGE_ID}")
          VERSIONS+=("${VERSION}")

        done < /tmp/daap-changed-paths.txt

        # Write output files for the collect-outputs step
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
          touch /tmp/daap-published-packages.txt
          touch /tmp/daap-package-ids.txt
          touch /tmp/daap-versions.txt
          echo "::notice::No packages were published in this run."
        fi

    # ── Step 6: Set action outputs ───────────────────────────────────────────
    - name: Collect outputs
      id: collect-outputs
      shell: bash
      run: |
        set -euo pipefail

        if [[ -s /tmp/daap-published-packages.txt ]]; then
          {
            echo "published-packages<<EOF"
            cat /tmp/daap-published-packages.txt
            echo "EOF"

            echo "package-ids<<EOF"
            cat /tmp/daap-package-ids.txt
            echo "EOF"

            echo "versions<<EOF"
            cat /tmp/daap-versions.txt
            echo "EOF"
          } >> "$GITHUB_OUTPUT"
        else
          {
            echo "published-packages="
            echo "package-ids="
            echo "versions="
          } >> "$GITHUB_OUTPUT"
        fi
