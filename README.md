# AAOS Buildbarn RBE Deployment

Kustomize overlay and deployment scripts for running [Buildbarn](https://github.com/buildbarn) as a local Remote Build Execution (RBE) backend for Android 15 AAOS builds.

This repository contains only the custom overlay files. It is applied on top of the upstream [bb-deployments](https://github.com/buildbarn/bb-deployments) repository via Kustomize.

## Prerequisites

- **Host**: Debian 12 (or similar) with 16+ cores and 240GB+ RAM
- **Docker CE** installed and running
- **k3d** (k3s-in-Docker): cluster management
- **kubectl**: Kubernetes CLI
- **kustomize**: built into `kubectl apply -k` (or standalone)
- **repo** tool: [Android repo](https://source.android.com/docs/setup/download#installing-repo)
- **~300GB disk** for AOSP source tree

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  AOSP Build Host                                            │
│                                                             │
│  ┌──────────┐    gRPC :8980    ┌──────────────────────────┐ │
│  │ reproxy  │ ───────────────► │  k3d cluster "buildbarn" │ │
│  │ (soong)  │                  │                          │ │
│  └──────────┘                  │  frontend (:8980)        │ │
│                                │    ├── scheduler (:8982) │ │
│                                │    │     └── worker x4   │ │
│                                │    │         (8 conc ea) │ │
│                                │    └── storage (1 shard) │ │
│                                │                          │ │
│                                │  browser (:8081/7984)    │ │
│                                └──────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Components

| Component | Kind | Replicas | Description |
|-----------|------|----------|-------------|
| **bb-storage** | StatefulSet | 1 | CAS and action cache on local PVC (50Gi) |
| **bb-scheduler** | Deployment | 1 | Routes actions to workers; `platformKeyExtractor: static` |
| **bb-worker** | Deployment | 4 | 8 concurrent actions each = 32 total slots; tmpfs-backed build/cache dirs |
| **bb-runner** | Sidecar | (in worker) | Custom `aaos-runner:local` image with Android build deps (JDK 17, Python 3, etc.) |
| **bb-frontend** | Deployment | 1 | gRPC endpoint on port 8980; proxies Execute/CAS/AC to scheduler/storage |
| **bb-browser** | Deployment | 1 | Web UI accessible on port 8081 |

## Repository Structure

```
aaos-rbe-deploy/
├── README.md
├── local-dev/
│   ├── kustomization.yaml          # Kustomize overlay (references ../kubernetes from bb-deployments)
│   ├── config/
│   │   ├── common.libsonnet        # Shared: single storage shard, browser URL, message sizes
│   │   ├── browser.jsonnet
│   │   ├── frontend.jsonnet         # gRPC :8980, scheduler routing, CAS/AC proxy
│   │   ├── runner-ubuntu22-04.jsonnet
│   │   ├── scheduler.jsonnet        # platformKeyExtractor: static, 1800s default timeout
│   │   ├── storage.jsonnet          # Local block-device CAS (48GB) + AC (20MB)
│   │   └── worker-ubuntu22-04.jsonnet  # 8 concurrency, 512MB cache, native build dirs
│   ├── docker/
│   │   └── aaos-runner/
│   │       └── Dockerfile           # Ubuntu 22.04 + Android build deps
│   ├── rbe_config/
│   │   ├── buildbarn.json           # reproxy config (RBE_service, exec strategies)
│   │   └── empty_creds.json         # Empty credential file for reproxy
│   ├── browser-local.yaml
│   ├── browser-service-patch.yaml   # LoadBalancer + port 80 -> 7984
│   ├── frontend-local.yaml          # No CPU limit, 16Gi memory limit
│   ├── scheduler-local.yaml
│   ├── storage-local.yaml           # No CPU limit, 16Gi memory limit
│   ├── storage-pvc-patch.yaml       # CAS PVC set to 50Gi
│   ├── worker-aaos-image-patch.yaml # Swap runner image to aaos-runner:local
│   ├── worker-local.yaml            # 4 replicas, no CPU limit, 32Gi memory limit
│   └── worker-tmpfs-patch.yaml      # tmpfs emptyDir (16Gi) for /worker volume
└── scripts/
    ├── sync-aosp.sh                 # Initialize and sync Android 15 AOSP source
    ├── setup-cluster.sh             # Create k3d cluster with port mappings
    ├── deploy.sh                    # Build image, import, clone bb-deployments, apply
    ├── start-build.sh               # Copy RBE config, envsetup, lunch, build
    └── teardown.sh                  # Delete cluster, remove images, clean up
```

## Deployment Steps

### 1. Clone this repository

```bash
git clone <this-repo-url> aaos-rbe-deploy
cd aaos-rbe-deploy
```

### 2. Sync AOSP source

If you don't already have an Android 15 source tree:

```bash
./scripts/sync-aosp.sh /path/to/aosp
```

This initializes and syncs the `android-15.0.0_r1` branch. You can override the branch with `AOSP_BRANCH` and parallelism with `SYNC_JOBS`:

```bash
AOSP_BRANCH=android-15.0.0_r1 SYNC_JOBS=16 ./scripts/sync-aosp.sh /path/to/aosp
```

The script also installs the `repo` tool to `~/.local/bin/` if not already available.

### 3. Create the k3d cluster

```bash
./scripts/setup-cluster.sh
```

This creates a k3d cluster named `buildbarn` with port mappings:
- `8980:8980` - gRPC frontend (reproxy connects here)
- `8081:80` - bb-browser web UI

### 4. Deploy Buildbarn

```bash
./scripts/deploy.sh
```

This script:
1. Builds the `aaos-runner:local` Docker image
2. Imports it into the k3d cluster
3. Clones upstream `bb-deployments` (if not already present at `../bb-deployments`)
4. Copies the `local-dev/` overlay into the clone
5. Runs `kubectl apply -k`

### 5. Wait for pods to be ready

```bash
kubectl -n buildbarn get pods -w
```

All pods should reach `Running` status. The storage pod may take a moment to initialize its PVC.

### 6. Copy RBE config to AOSP tree

```bash
cp local-dev/rbe_config/buildbarn.json <aosp>/build/soong/rbe_config/
cp local-dev/rbe_config/empty_creds.json <aosp>/build/soong/rbe_config/
```

### 7. Run the build

Use the helper script (recommended — it exports all required env vars):

```bash
AOSP_ROOT=/path/to/aosp ./scripts/start-build.sh
```

Or manually from your AOSP source root:

```bash
export USE_RBE=1
export NINJA_REMOTE_NUM_JOBS=72
export RBE_service=localhost:8980
export RBE_service_no_auth=true
export RBE_service_no_security=true
export RBE_use_application_default_credentials=false
export RBE_credential_file=build/soong/rbe_config/empty_creds.json
export RBE_CXX=1 RBE_JAVAC=1 RBE_R8=1 RBE_D8=1
export RBE_DIR=prebuilts/remoteexecution-client/live
export RBE_CXX_EXEC_STRATEGY=remote_local_fallback
export RBE_JAVAC_EXEC_STRATEGY=remote_local_fallback
export RBE_R8_EXEC_STRATEGY=remote_local_fallback
export RBE_D8_EXEC_STRATEGY=remote_local_fallback
source build/envsetup.sh
lunch sdk_car_x86_64-trunk_staging-userdebug
m
```

**Important**: Soong does not read `buildbarn.json` automatically. All `RBE_*` variables must be exported in the shell environment before the build. The `start-build.sh` script handles this.

## Key Configuration Decisions

### NINJA_REMOTE_NUM_JOBS=72

Total worker slots: 4 replicas x 8 concurrency = 32. Setting remote jobs to ~2x the slot count keeps the pipeline full without overwhelming reproxy's connection pool. The default of 500 causes `dial_timeout` failures as reproxy tries to open hundreds of simultaneous gRPC streams to the frontend.

### tmpfs worker volumes (`worker-tmpfs-patch.yaml`)

Workers download inputs, compile, and upload results — all through disk by default. With 32 concurrent actions this generates heavy I/O (~95MB/s writes). Replacing the worker volume with `emptyDir: { medium: Memory, sizeLimit: 16Gi }` eliminates disk I/O entirely. **Caveat**: tmpfs counts against the container memory cgroup, so memory limits must accommodate both process memory and tmpfs usage (hence the 32Gi memory limit on workers).

### No CPU limits on workers/storage/frontend

Kubernetes CPU limits cause CFS throttling even when host cores are idle. The storage pod was the cluster bottleneck when throttled at 4 cores. Removing CPU limits (keeping only requests for scheduling) allows full utilization of all host cores. Only the scheduler retains a CPU limit since it is lightweight.

### 32Gi memory limits on workers

With 16Gi tmpfs `sizeLimit` plus process memory for 8 concurrent compilation actions, workers need generous memory limits. 4Gi caused `OOMKilled` restarts.

### `platformKeyExtractor: static` (scheduler)

Android's reproxy sends platform properties (`container-image`, `OSFamily`, etc.) that don't match any Buildbarn worker pool name. The `static` extractor ignores platform properties entirely, routing all actions to the single worker pool. Without this, actions queue indefinitely waiting for a matching pool.

### 50Gi CAS storage

All CAS and AC data lives on one `storage-0` pod with a 50Gi PVC. The CAS block store is configured for 48GB and the AC for 20MB. A full AAOS build populates ~40GB of CAS data (toolchain binaries, source inputs, compilation outputs). The original 10Gi/8GB configuration caused constant eviction and `Object not found` errors on workers. On first build with a cold CAS, expect the initial actions to fail remotely while the toolchain (~3GB of clang libraries and headers) is uploaded; `remote_local_fallback` handles this transparently.

### `remote_local_fallback` execution strategy

Actions that fail remotely (missing tools, platform issues, unsupported action types) fall back to local execution. Essential during initial setup and for action types that Buildbarn's runner doesn't support. Configured per action type in `buildbarn.json`:
- `RBE_CXX_EXEC_STRATEGY`: `remote_local_fallback`
- `RBE_JAVAC_EXEC_STRATEGY`: `remote_local_fallback`
- `RBE_R8_EXEC_STRATEGY`: `remote_local_fallback`
- `RBE_D8_EXEC_STRATEGY`: `remote_local_fallback`

### Empty credentials file (`empty_creds.json`)

reproxy requires `RBE_credential_file` to be set but Buildbarn uses no authentication. The file must be **0 bytes** (a valid empty protobuf message). A file containing `{}` (JSON) does not work — reproxy expects protobuf format and will fail to parse it, falling back to Application Default Credentials.

Additionally, `RBE_use_application_default_credentials` must be explicitly set to `false`. Soong's `rbeAuth()` function defaults to `true` if no credential flag is found in the environment, which causes `Unable to authenticate with RBE` errors on non-Google infrastructure.

The `RBE_service_no_auth` and `RBE_service_no_security` flags disable TLS and auth on the gRPC connection to the Buildbarn frontend.

### `RBE_service` without `grpc://` prefix

The `RBE_service` value must be `localhost:8980` without a `grpc://` prefix. reproxy adds the scheme internally. Including the prefix causes connection failures.

## Troubleshooting

### `Unable to authenticate with RBE` / Application Default Credentials error

Soong's `rbeAuth()` defaults to `RBE_use_application_default_credentials=true` if no credential flag is found in the environment. This causes reproxy to attempt Google ADC, which fails on non-Google infrastructure.

- Ensure `RBE_use_application_default_credentials=false` is exported
- Ensure `RBE_credential_file=build/soong/rbe_config/empty_creds.json` is exported
- Ensure `empty_creds.json` is 0 bytes (not `{}`)
- Use `scripts/start-build.sh` which exports all required variables

### reproxy `dial_timeout`

reproxy cannot connect to the frontend or is overwhelming it with too many concurrent requests.

- Verify the frontend pod is running: `kubectl -n buildbarn get pods -l app=frontend`
- Reduce `NINJA_REMOTE_NUM_JOBS` (try 32, matching total worker slots)
- Check frontend logs: `kubectl -n buildbarn logs deploy/frontend`

### Worker OOMKilled

Workers are exceeding their memory limit. Remember that tmpfs usage counts against the memory cgroup.

- Check current limits: `kubectl -n buildbarn describe pod -l app=worker-ubuntu22-04`
- Increase memory limits in `worker-local.yaml` (must cover tmpfs sizeLimit + process memory for all concurrent actions)

### Low CPU utilization despite queued actions

Kubernetes CPU limits cause CFS throttling even when host CPUs are idle.

- Remove CPU limits from storage, worker, and frontend pods (keep only `requests`)
- Check for throttling: `kubectl -n buildbarn top pods`

### Stale reproxy state

reproxy can get stuck if a previous build was interrupted.

```bash
pkill reproxy
rm -f /tmp/reproxy* /tmp/RBE*
rm -f out/.lock
```

### `Object not found` / `FailedPrecondition` on first build (cold CAS)

On the first build after deploying (or after storage pod restart), the CAS is empty. reproxy must upload the entire input tree (~3GB for the clang toolchain alone) before remote execution can succeed. Early actions will fail remotely and fall back to local — this is expected with `remote_local_fallback`. The CAS warms up progressively and remote execution success rate increases as more inputs are uploaded. A full AAOS build populates ~40GB of CAS data.

- Monitor CAS usage: `sudo docker exec k3d-buildbarn-server-0 du -sh /var/lib/rancher/k3s/storage/pvc-*`
- Check reproxy upload errors: `grep "failed to upload" <aosp>/out/soong/.temp/rbe/reproxy.*.INFO.*`

### Actions queuing but not executing

Workers may not be synchronized with the scheduler.

- Check scheduler logs: `kubectl -n buildbarn logs deploy/scheduler-ubuntu22-04`
- Verify workers are connecting: look for "synchronizing" messages
- Confirm `platformKeyExtractor: static` is set in `config/scheduler.jsonnet`

### bb-browser not accessible

The browser UI should be available at `http://localhost:8081`.

- Verify the service: `kubectl -n buildbarn get svc browser`
- Alternative: `kubectl -n buildbarn port-forward svc/browser 7984:7984` then visit `http://localhost:7984`

## Teardown

To remove the Buildbarn cluster and clean up resources:

```bash
./scripts/teardown.sh
```

This will:
1. Delete the k3d cluster (`buildbarn`) and all Kubernetes resources within it
2. Remove the `aaos-runner:local` Docker image
3. Clean up any stale reproxy temp files (`/tmp/reproxy*`, `/tmp/RBE*`)

The `bb-deployments` clone and AOSP source tree are **not** removed automatically. Delete them manually if no longer needed.

To recreate the environment after teardown, run `setup-cluster.sh` and `deploy.sh` again.

## Upstream Reference

This overlay is designed against the `main` branch of [buildbarn/bb-deployments](https://github.com/buildbarn/bb-deployments). The `kustomization.yaml` references `../kubernetes` as its base, which is the standard Kubernetes deployment from that repo. If upstream changes break the overlay, pin to a known-working commit.
