# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Kustomize-based Kubernetes overlay that deploys [Buildbarn](https://github.com/buildbarn) as a local Remote Build Execution (RBE) backend for Android 15 AAOS (Android Automotive OS) builds. It runs entirely in a local k3d cluster and is designed for single-machine deployments.

The repo contains **only the overlay and customizations** — the upstream Buildbarn Kubernetes manifests come from `buildbarn/bb-deployments` (cloned to `../bb-deployments` during deployment).

## Deployment Commands

```bash
# Full pipeline
./scripts/sync-aosp.sh /path/to/aosp   # Sync Android 15 source (~300GB)
./scripts/setup-cluster.sh              # Create k3d cluster "buildbarn" (ports 8980, 8081)
./scripts/deploy.sh                     # Build runner image, import to k3d, apply overlay
kubectl -n buildbarn get pods -w        # Wait for pods to be ready
AOSP_ROOT=/path/to/aosp ./scripts/start-build.sh  # Run AAOS build with RBE

# Cleanup
./scripts/teardown.sh                   # Delete cluster, images, temp files
```

There are no tests or linters in this repo — it is purely infrastructure configuration.

## Architecture

```
AOSP Build Host (reproxy on localhost)
    ↓ gRPC :8980
┌──────────────────────────────────────┐
│  k3d cluster "buildbarn"             │
│                                      │
│  Frontend (1 replica) :8980          │  ← gRPC entry point
│    → routes actions to Scheduler     │
│    → proxies CAS/AC to Storage       │
│                                      │
│  Scheduler (1 replica) :8982/:8983   │  ← static platform extraction
│    → routes all actions to one pool  │
│                                      │
│  Workers (4 replicas, 8 concurrent)  │  ← 32 total execution slots
│    → aaos-runner:local image         │
│    → tmpfs /worker (16Gi in-memory)  │
│                                      │
│  Storage (1 StatefulSet) :8981       │  ← CAS: 200GB, AC: 20MB
│    → PVC: 210Gi                      │
│                                      │
│  Browser (1 replica) :7984           │  ← Web UI at localhost:8081
└──────────────────────────────────────┘
```

**Execution flow:** reproxy → frontend → scheduler → worker (downloads inputs from CAS, compiles in tmpfs, uploads outputs) → reproxy fetches results.

## Repository Structure

- **`local-dev/kustomization.yaml`** — Kustomize entry point; overlays upstream `../kubernetes/` base, replaces ConfigMap, applies patches
- **`local-dev/config/*.jsonnet`** — Buildbarn component configs (frontend, scheduler, storage, worker, browser, runner); `common.libsonnet` is the shared library
- **`local-dev/*-local.yaml`** — Strategic merge patches (replicas, resource limits)
- **`local-dev/*-patch.yaml`** — JSON patches (tmpfs volumes, PVC size, image swap, service type)
- **`local-dev/docker/aaos-runner/Dockerfile`** — Ubuntu 22.04 with Android build deps (JDK 17, Python 3, build tools, 32-bit libs)
- **`local-dev/rbe_config/`** — reproxy client config; `empty_creds.json` must be exactly 0 bytes (valid empty protobuf)
- **`scripts/`** — Bash scripts for each deployment lifecycle step

## Key Configuration Details

**Naming conventions:**
- `*-local.yaml` = strategic merge patches for K8s resource overrides
- `*-patch.yaml` = JSON patches for specific field modifications
- `*.jsonnet` = Buildbarn configs; `*.libsonnet` = shared Jsonnet libraries

**Port assignments:** 8980 (gRPC frontend), 8981 (storage), 8982 (scheduler client), 8983 (scheduler worker), 7984 (browser HTTP), 9980 (diagnostics/metrics)

**Critical design decisions:**
- `platformKeyExtractor: static` in scheduler — Android reproxy sends platform properties that don't match any pool name, so the scheduler ignores them and routes everything to the default pool. Changing this will cause actions to queue forever.
- `NINJA_REMOTE_NUM_JOBS=72` — Set to ~2x worker slots (32). The default 500 causes `dial_timeout` errors by overwhelming the frontend.
- tmpfs worker volumes — `emptyDir: {medium: Memory}` eliminates disk I/O but counts against the container's memory cgroup, hence the 32Gi memory limits (16Gi tmpfs + process headroom).
- No CPU limits on workers/storage/frontend — avoids Kubernetes CFS throttling on idle cores.
- `remote_local_fallback` execution strategy — first build has remote failures (cold CAS); transparent fallback to local execution is expected behavior.

**Gotchas:**
- `empty_creds.json` must be 0 bytes (empty protobuf), not JSON `{}`. Soong requires `RBE_credential_file` even with no auth.
- `RBE_service=localhost:8980` — no `grpc://` prefix.
- Soong does **not** read `buildbarn.json` — all `RBE_*` variables must be exported in the shell before building. The JSON file is informational only.
- `RBE_use_application_default_credentials=false` must be set explicitly or Soong defaults to Google ADC and fails with auth errors.
- After failed builds, clean reproxy state: `pkill reproxy && rm -f /tmp/reproxy* /tmp/RBE* out/.lock`
