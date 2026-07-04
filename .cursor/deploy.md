# k3s deploy guide (for agents)

How to deploy **mainfactory** to a local k3s cluster (WSL/dev). Handlers are delivered via a **local Docker registry** on `localhost:5000`; k3s pulls images from there.

## Cluster layout

| Resource | Namespace | Access |
|----------|-----------|--------|
| Postgres | `mainfactory` | `postgresql://mes:mes@postgres.mainfactory.svc:5432/mes` |
| bot-handler | `mainfactory` | NodePort **30900** (TCP `:9000` in pod) |
| server-handler | `mainfactory` | NodePort **30901** (TCP `:9001` in pod) |

MES Python app is **not** deployed to k3s yet — only Postgres + Go handlers. Run migrations from the host.

## Prerequisites

- k3s running (`systemctl is-active k3s` → `active`)
- Docker available (`docker info`)
- `kubectl` works without sudo (`kubectl get nodes`)

## One-time host setup (user must run with sudo)

Agents **cannot** run these interactively (sudo password). Ask the user once, then proceed.

```bash
cd deploy/k3s
sudo ./setup-kubectl-access.sh    # kubeconfig in ~/.kube/config
sudo ./setup-registry.sh          # registry:2 on 127.0.0.1:5000 + /etc/rancher/k3s/registries.yaml
```

Verify before deploy:

```bash
kubectl get nodes
curl -sf http://localhost:5000/v2/
```

## Standard deploy (agent can run)

From repo root:

```bash
cd deploy/k3s
./deploy.sh
```

This runs:

1. `push-images.sh` — `docker build` both handlers, tag & push to `localhost:5000/`
2. `apply.sh` — `kubectl apply` namespace, postgres, bot-handler, server-handler
3. `kubectl rollout restart` + wait for bot-handler and server-handler

Step-by-step alternative:

```bash
./push-images.sh
./apply.sh
kubectl rollout restart deployment/bot-handler deployment/server-handler -n mainfactory
```

## Apply migrations (from host)

Postgres is ClusterIP only. Port-forward, then migrate:

```bash
kubectl port-forward -n mainfactory svc/postgres 15432:5432 &
pip install 'psycopg[binary]>=3.1' --break-system-packages   # Ubuntu 24.04 PEP 668
DATABASE_URL=postgresql://mes:mes@127.0.0.1:15432/mes python3 mes/scripts/migrate.py
```

Do **not** use `pip install -e mes/` — setuptools fails on flat-layout (`notebooks/`, `migrations/`).

## Verify deployment

```bash
kubectl get pods -n mainfactory
kubectl get deployment -n mainfactory -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.spec.template.spec.containers[0].image}{"\n"}{end}'

printf 'PING\n' | nc -w 2 127.0.0.1 30900   # expect PONG (bot)
printf 'PING\n' | nc -w 2 127.0.0.1 30901   # expect PONG (server)
```

Handler images must be `localhost:5000/bot-handler:latest` and `localhost:5000/server-handler:latest` with `imagePullPolicy: Always`.

## Scripts reference

| Script | sudo? | Purpose |
|--------|-------|---------|
| `setup-kubectl-access.sh` | yes | Persistent kubectl access for dev user |
| `setup-registry.sh` | yes | Local registry + k3s insecure mirror |
| `push-images.sh` | no | Build and push handler images |
| `apply.sh` | no | Apply all k8s manifests |
| `deploy.sh` | no | push + apply + rollout restart |

## Troubleshooting

**`push-images.sh`: Registry not reachable**

- User has not run `sudo ./setup-registry.sh`, or registry container stopped.
- Fix: `docker start mainfactory-registry` or re-run setup script.

**`kubectl`: permission denied on k3s.yaml**

- Run `sudo ./setup-kubectl-access.sh` once.

**Handler pod `ImagePullBackOff`**

- Image not in registry: run `./push-images.sh`.
- k3s mirror missing: check `/etc/rancher/k3s/registries.yaml`, restart k3s.
- Do **not** use privileged import Jobs or `sudo k3s ctr images import` — registry is the supported path.

**Docker build: `unknown instruction: FROM`**

- File is UTF-16, not UTF-8. Re-save as UTF-8 (all project text files must be UTF-8).

**Postgres pod slow to start**

- Wait for PVC bind and `postgres:16-alpine` pull (~1–2 min first time).

## Do not

- Import images via `docker save | sudo k3s ctr images import` (legacy; replaced by registry).
- Deploy MES Python to k3s without a manifest (not in repo yet).
- Commit secrets beyond dev defaults (`mes/mes` in `postgres/secret.yaml` is dev-only).
