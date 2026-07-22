# k8s-homelab-cluster

Infrastructure-as-code for my home Kubernetes cluster. Every component is deployed with [Helmfile](https://helmfile.readthedocs.io/), one `helmfile.yaml` per directory.

## Cluster

| Node | Hardware | Location |
|---|---|---|
| optiplex-1 | Dell Optiplex 3060 (micro form factor) — i5 8th gen, 16GB DDR4 3200MHz (1 slot, upgradable to 32GB), 1TB Samsung SATA SSD | On switch |
| optiplex-2 | Dell Optiplex 3060 (micro form factor) — i5 8th gen, 16GB DDR4 3200MHz (1 slot, upgradable to 32GB), 1TB Samsung SATA SSD | On switch |
| rpi5 | Raspberry Pi 5, 8GB RAM, 512GB NVMe SSD | Remote (different region) |

Switch: TP-Link SG108E. The two Optiplex nodes are wired to it directly; the Pi lives elsewhere and joins the cluster over [NetBird](https://netbird.io), a WireGuard-based mesh VPN.

## Layout

```
.
├── cloudflare/     cloudflared tunnel — exposes internal services externally
├── infisical/      secrets management (standalone server + k8s operator)
├── longhorn/       distributed block storage (CSI)
├── navidrome/      (planned — music server)
├── outline/        internal wiki/docs, backed by the built-in postgres+redis
└── traefik/        ingress controller (DaemonSet, binds host ports 80/443)
```

## How it's deployed

Each folder is self-contained: a `helmfile.yaml` and an optional `values.yaml`. To deploy one component:

```bash
cd <component>
helmfile apply
```

If bootstrapping from scratch, deploy in this order since most other services depend on ingress, storage, and secrets being available first: `traefik` → `longhorn` → `infisical` → `cloudflare` → everything else.

## Secrets

Secrets are meant to be managed through Infisical (`infisical/`), synced into the cluster via the operator's `InfisicalAuth`/`InfisicalConnection` CRDs rather than committed as plain `Secret` manifests.
