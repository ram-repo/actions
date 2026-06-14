# DAAP Shared GitHub Actions

Shared composite actions for building, publishing, and deploying DAAP data
product packages via the DAAP CLI Docker image.

---

## Repository layout

```
df-actions/                              ← this repo (grid-platform/df-actions)
│
├── daap-build-publish/
│   ├── action.yml                       ← composite action definition
│   └── scripts/
│       └── build-publish.sh            ← inner loop: resolve → change-detect → build → publish
│
└── daap-deploy/
    ├── action.yml                       ← composite action definition
    └── scripts/
        └── deploy.sh                   ← generates + applies Kubernetes Job manifest

consumer-workflows/                      ← example consumer workflow files
├── mono-repo/
│   └── .github/workflows/
│       └── daap-publish-deploy.yml     ← merge-as-release, multiple products
├── microservice-gated/
│   └── .github/workflows/
│       └── ci.yml                      ← data product co-located with microservice
└── tag-as-release/
    └── .github/workflows/
        └── daap-publish-deploy.yml     ← production gate is a tag push
```

---

## Quick reference: which consumer workflow to use?

| Situation | Use |
|---|---|
| Multiple independent data products in one repo | `mono-repo/daap-publish-deploy.yml` |
| Data product co-located with a microservice; must only ship with that microservice version | `microservice-gated/ci.yml` |
| Production releases are controlled by a Git tag (not by merging to main) | `tag-as-release/daap-publish-deploy.yml` |

---

## Action: `daap-build-publish`

```yaml
- uses: grid-platform/df-actions/daap-build-publish@v1
  with:
    # Required
    data-product-paths:      data-products      # or daap/my-product (explicit mode)
    data-assets-path:        data-assets
    artifactory-username:    ${{ secrets.ARTIFACTORY_USR }}
    artifactory-password:    ${{ secrets.ARTIFACTORY_PWD }}
    artifactory-package-url: ${{ secrets.ARTIFACTORY_PACKAGE_URL }}   # or SNAPSHOT_URL

    # Optional — change detection & version check
    base-sha:           ${{ github.event.pull_request.base.sha }}
    head-sha:           ${{ github.sha }}
    skip-version-check: "false"   # true for all non-PR triggers
    allow-overwrite:    "true"    # false for production merge-as-release
```

**Outputs**

| Output | Description |
|---|---|
| `published-packages` | Newline-separated `package_id` values — pass to `daap-deploy` |
| `package-ids` | Same list (same order as input paths) |
| `versions` | Matching version strings |

---

## Action: `daap-deploy`

```yaml
- uses: grid-platform/df-actions/daap-deploy@v1
  with:
    # Required
    packages:    ${{ needs.publish.outputs.published-packages }}
    kube-config: ${{ secrets.KUBE_CONFIG }}

    # Optional
    method:               Overwrite   # or Upgrade
    retry-limit:          "0"
    namespace:            default
    job-timeout:          "600"
    custom-commands: |
      daap package download sandbox-data
    extra-env: |
      MY_VAR=value
    extra-secret-refs:    "my-secret another-secret"
    extra-configmap-refs: "my-configmap"
```

**Outputs**

| Output | Description |
|---|---|
| `job-name` | Kubernetes Job name (`daap-deploy-<run_id>`) |
| `status` | `Succeeded` or `Failed` |

---

## Required secrets (in consuming repo)

| Secret | Used by |
|---|---|
| `ARTIFACTORY_USR` | `daap-build-publish` |
| `ARTIFACTORY_PWD` | `daap-build-publish` |
| `ARTIFACTORY_PACKAGE_URL` | `daap-build-publish` (production) |
| `ARTIFACTORY_SNAPSHOT_URL` | `daap-build-publish` (snapshot) |
| `KUBE_CONFIG` | `daap-deploy` |

The following Kubernetes Secrets are **pre-existing cluster resources** (not
GitHub secrets) and must exist in the target namespace before first deploy:

- `discover-admin-user-password`
- `discover-api-user-password`
- `explore-admin-user-password`
- `artifactory-credentials` (optional)

---

## Key design rules

- **One call per action** — `daap-build-publish` iterates all paths internally;
  `daap-deploy` deploys all packages in a single Job. No matrix needed.
- **Explicit inputs** — the caller declares paths; no auto-discovery of fixed
  directories.
- **Version bump enforcement** — runs automatically on open PRs
  (`skip-version-check: false`). A PR comment is posted on failure.
- **Trigger-agnostic actions** — the actions never inspect `github.event_name`.
  All routing logic (snapshot vs production, `allow-overwrite`, `skip-version-check`)
  is controlled by the consumer workflow via action inputs.
- **Teams outside `grid-platform`** — fork the action repo into your own org
  and maintain it. Subscribe to releases in the canonical repo for changelogs.
