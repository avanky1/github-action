# Next.js → EC2 via GitHub Actions

A minimal Next.js app that is **built in GitHub Actions** and only the finished
build is shipped to a small EC2 instance (1 vCPU / 2 GB is enough).

Why? `next build` is memory-hungry. Building on a tiny server can OOM. Here the
GitHub runner does the heavy work, then CI copies the *standalone* output to the
server and restarts it with PM2. Nothing is compiled on EC2.

## How it works

```
push to main
   │
   ▼
GitHub Actions runner
   ├─ npm ci
   ├─ npm run build            (output: .next/standalone)
   ├─ assemble public + static into standalone/
   ├─ rsync standalone/ ─────────────► EC2: releases/<release-id>/
   ├─ ssh deploy.sh ─────────────────► flip `current` symlink, PM2 reload
   │                                    + health check, auto-rollback on failure
   └─ (Nginx config synced) ─────────► reverse-proxy mirror1.downly.sbs → :3000
```

`next.config.mjs` sets `output: 'standalone'`, which produces a self-contained
`server.js` plus the minimal `node_modules` it needs.

### Zero-downtime release layout on the server

```
$APP_DIR/
  releases/
    20261125132448-95c8515/   ← each push = a fully-built, immutable release
    20261125132210-e409978/
  current -> releases/20261125132448-95c8515   ← atomic symlink (PM2 runs this)
  ecosystem.config.js
```

`scripts/deploy.sh` points `current` at the new release, reloads PM2, polls
`/api/health`, and if it's not healthy **rolls the symlink back** to the
previous release. Only the last 5 releases are kept (`KEEP_RELEASES`).

## One-time EC2 setup

SSH into the instance and install Node 22 + PM2:

```bash
# Node 22 (Amazon Linux / any systemd distro)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -   # Debian/Ubuntu
sudo apt-get install -y nodejs                                       # or: sudo dnf install -y nodejs

# PM2 process manager
sudo npm install -g pm2
pm2 startup            # follow the printed command to enable boot start
```

Create the deploy directory:

```bash
mkdir -p ~/github-ac
```

### Create a deploy key for GitHub Actions

On your **local machine** (or the server):

```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f deploy_key -N ""
```

- Add the **public** key (`deploy_key.pub`) to the server's
  `~/.ssh/authorized_keys`.
- Put the **private** key (`deploy_key` contents) into the `EC2_SSH_KEY` secret.

Open port **3000** in the EC2 Security Group (or put Nginx in front and only
open 80/443). PM2 runs the app on `0.0.0.0:3000`.

## GitHub repository secrets

Settings → Secrets and variables → Actions → New repository secret:

| Secret        | Example                          | Meaning                          |
| ------------- | -------------------------------- | -------------------------------- |
| `EC2_HOST`    | `ec2-1-2-3-4.compute.amazonaws.com` | Public DNS or IP              |
| `EC2_USER`    | `ubuntu` or `ec2-user`           | SSH user                         |
| `EC2_SSH_KEY` | contents of `deploy_key`         | Private key (OpenSSH format)     |
| `EC2_APP_DIR` | `/home/ubuntu/github-ac`         | Target dir on the server         |

Then push to `main` (or run the workflow manually) and watch the **Actions** tab.

## Local development

```bash
npm install
npm run dev          # http://localhost:3000
npm run build        # verify the production build locally
```

## Custom subdomain (mirror1.downly.sbs)

The workflow installs `nginx` (Debian/Ubuntu) and deploys
`nginx/mirror1.downly.sbs.conf`, which reverse-proxies
`mirror1.downly.sbs:80` → `127.0.0.1:3000`. Only the app's port 3000 listens
publicly on the server; Nginx fronts it on port 80.

One-time manual steps (not automatable from CI):

1. **DNS**: at your domain registrar create an `A` record
   `mirror1` → `<EC2_PUBLIC_IP>` (`54.66.128.241`). Verify:
   ```bash
   nslookup mirror1.downly.sbs
   ```
2. **Security group**: allow inbound `HTTP (80)` from `0.0.0.0/0`.
3. Push to `main` (or run the workflow) to install Nginx + deploy the site.

Then browse `http://mirror1.downly.sbs`.

### HTTPS (optional)

After HTTP works, on the server:

```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d mirror1.downly.sbs
```

## Notes

- Health endpoint: `GET /api/health` returns `{ status, uptime, timestamp }`.
- Port / memory are configured in `ecosystem.config.js`
  (`max_memory_restart: 400M` keeps things safe on a 2 GB box).
- `rsync --delete` writes each build into its own `releases/<id>/` dir;
  `scripts/deploy.sh` flips the `current` symlink and keeps the last 5 releases.
- Failed health check ⇒ automatic rollback to the previous release (CI fails too).
- The `releases/<id>/` dirs include their own `node_modules`, so each release is
  self-contained; watch disk on an 8 GB EBS (5 releases is fine).
