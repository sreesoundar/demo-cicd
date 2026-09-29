# demo-cicd

Throwaway app used to prove out a GitHub Actions CI/CD pipeline before rolling
the same shape into the real TimberCore repos. ClickUp: 14yp17zn2mr.

- Repo: https://github.com/sreesoundar/demo-cicd (public)
- Live: http://13.238.155.12/ (EC2 `timbercore-demo-cicd-server`, ap-southeast-2) — **http only**, see [HTTPS](#https)
- Local: `C:\SREE\dev\demo-cicd`

No TimberCore code, nothing pointing at staging or prod. The one shared thing
is the EC2 security group — see [Known gaps](#6-known-gaps).

## 1. Demo app

Two halves, deliberately mirroring the real stack so the workflow transfers
one-for-one:

| | |
|---|---|
| **Frontend** | Vite + React 19 + TypeScript, same as `TimberCore/src/UI`. Plus `vitest`, one pure util (`src/greet.ts`) and its test |
| **Backend** | `api/` — net8.0 webapi + xunit, one solution (`api/Demo.sln`), same target framework as TimberCore |

Both halves have a real test with a real assertion, so the test steps have
something that can actually fail.

## 2. Pipeline

One workflow file: `.github/workflows/ci-cd.yml`. Three jobs: `ci` (frontend),
`backend`, and `deploy`.

### Triggers
- `pull_request` → `main` or `develop`: runs `ci` and `backend`.
- `push` → `main`: runs `ci` and `backend`. No deploy.
- `push` → `develop`: runs `ci` and `backend`, then `deploy` to the demo EC2.
- `concurrency` cancels a superseded run on the same ref, so a fast follow-up
  push doesn't race the earlier deploy.

### Frontend (`ci` job)
1. `actions/checkout`
2. `actions/setup-node` @ Node 22 with `cache: npm` (restores `~/.npm` keyed on
   `package-lock.json` — turns a ~60s install into a few seconds)
3. `npm ci` — lockfile-exact install, fails if `package.json` and the lockfile
   have drifted apart (`npm install` would silently fix it up instead)
4. `npm run lint` — oxlint
5. `npm test` → `vitest run` (single run, not watch — watch mode never exits and
   would hang the runner)
6. `npm run build` — `tsc -b && vite build`, so a type error fails CI

### Backend (`backend` job)
Runs in parallel with `ci`, `working-directory: api`.

1. `actions/checkout`
2. `actions/setup-dotnet` @ 8.0.x
3. `dotnet restore Demo.sln`
4. `dotnet build Demo.sln -c Release --no-restore`
5. `dotnet test Demo.sln -c Release --no-build --logger "trx;..."` — results
   upload as an artifact on every run, `if: always()`, so a failure is
   inspectable without re-reading the log
6. On `develop` only: `dotnet publish -r linux-x64 --self-contained` and upload
   it as the `api` artifact (see [Why self-contained](#why-self-contained))

`cache: true` on `setup-dotnet` is deliberately **not** used: it requires
`packages.lock.json` files, which means committing to lock-file maintenance via
`RestorePackagesWithLockFile`. Restore is seconds on two small projects. For
TimberCore's larger solution it's worth revisiting, with that cost understood.

### Deploy (`deploy` job)
Target: **demo EC2** (Ubuntu 26.04, amd64), http://13.238.155.12/

```
GitHub Actions ──SSH──▶ EC2
                         ├── Nginx :80
                         │     ├── /       → /var/www/demo-ui   (React dist/)
                         │     └── /api/*  → 127.0.0.1:5000     (prefix stripped)
                         └── systemd demo-api → /var/www/demo-api/Api (self-contained)
```

- `ci` uploads `dist/` as the `ui` artifact and `backend` uploads the published
  API as `api` — both gated on `github.ref == 'refs/heads/develop'`, so PR and
  `main` runs build-and-verify without shipping anything.
- `deploy` `needs: [ci, backend]` — either half failing blocks the release.
- `deploy` downloads both artifacts, then over SSH:
  1. streams each one as a tar into its folder, replacing the old contents
     (tar, not rsync — rsync isn't guaranteed on the box)
  2. `chmod +x Api` — `upload-artifact` zips without Unix permissions, so the
     executable bit is lost in transit
  3. `sudo systemctl restart demo-api`
  4. **smoke test through Nginx**: `curl /api/weatherforecast` (retries while
     the API starts) and checks `/` returns the React shell. A deploy that
     copies files but doesn't serve fails the job.
- `vite.config.ts` has no `base` — Nginx serves from `/`. (Pages needed
  `/demo-cicd/`; that's gone with Pages.)

Nginx strips the `/api` prefix (`proxy_pass http://127.0.0.1:5000/;` — the
trailing slash does it), so `/api/weatherforecast` reaches the API as
`/weatherforecast` with no code change in the API.

#### Why self-contained
Ubuntu 26.04's package archive has no `aspnetcore-runtime-8.0`, so the API
brings its own runtime instead of the server installing one. Cost: a bigger
artifact (~70 MB) and the RID (`linux-x64`) must match the instance's CPU — an
ARM/Graviton instance needs `linux-arm64`. Gain: nothing .NET to install or
patch on the server, and the server can't drift from what CI tested.

#### Server setup (one-time)
[`deploy/setup-ec2.sh`](deploy/setup-ec2.sh), run once as the SSH user CI
deploys as:

```bash
scp -i tc-demo-cicd.pem deploy/setup-ec2.sh ubuntu@13.238.155.12:~
ssh -i tc-demo-cicd.pem ubuntu@13.238.155.12 "sudo bash ~/setup-ec2.sh"
```

It creates `/var/www/demo-ui` + `/var/www/demo-api` owned by that user (so CI
copies in without sudo), the `demo-api` systemd unit on `127.0.0.1:5000`, the
Nginx site at `/etc/nginx/conf.d/demo-cicd.conf` (removing Ubuntu's default
site), and a sudoers entry allowing **only** `systemctl restart demo-api`
without a password. Safe to re-run.

#### HTTPS
Not set up — Nginx listens on 80 only. Browsers that auto-upgrade to https
(or a corporate proxy, which shows `ERR_TUNNEL_CONNECTION_FAILED`) will fail;
type `http://` explicitly. HTTPS needs a real domain pointed at the instance
plus a certificate (certbot/Let's Encrypt) — AWS won't issue one for the
`ec2-*.amazonaws.com` hostname.

Runners are pinned to `ubuntu-24.04` rather than `ubuntu-latest`, which migrates
to Ubuntu 26 on 19 Oct 2026.

## 3. Secrets / credentials

Three **repository** secrets (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `EC2_HOST` | `13.238.155.12` |
| `EC2_USER` | `ubuntu` |
| `EC2_SSH_KEY` | full contents of `tc-demo-cicd.pem`, BEGIN/END lines included |

```bash
gh secret set EC2_HOST -b 13.238.155.12
gh secret set EC2_USER -b ubuntu
Get-Content tc-demo-cicd.pem -Raw | gh secret set EC2_SSH_KEY   # PowerShell
```

They must be on **this** repo — a secret set on another repo is invisible here,
and the job fails at *Configure SSH* with the variables printed as empty. Check
with `gh secret list`.

This is a long-lived key, unlike the OIDC token the Pages deploy used. It was
chosen because it works with no IAM changes. Its limits: anyone who can read
repo secrets holds a key to the box, and it needs port 22 open to all GitHub
runners (their IPs aren't fixed). The host key is trusted on first use
(`ssh-keyscan` each run, marked `ponytail:` in the workflow) — pin it via an
`EC2_KNOWN_HOSTS` secret beyond the demo.

For the real pipelines, use OIDC rather than long-lived keys:
configure an AWS IAM OIDC provider trusting GitHub, and have the deploy job
assume a role via `aws-actions/configure-aws-credentials`. Fall back to
`secrets.*` (repo or environment secrets) only for third-party services that
can't do OIDC. Note the frontend rule still applies — a `VITE_*` value injected
at build time is inlined into the public bundle, so it is config, never a secret.

Default token permissions are pinned to `contents: read` at workflow level, and
no job needs more — the EC2 deploy talks to the server over SSH, not the GitHub
API.

## 4. Gates

Branch protection is **live on `main`**, not just described:

| Rule | State |
|---|---|
| PR required before merge | yes |
| Required checks | `ci`, `backend` |
| Strict | yes — branch must be up to date before merge |
| Enforced on admins | yes — no bypass |
| Force push / deletion | blocked |
| Approvals required | **0** |

Approvals is 0 only because this is a solo repo and GitHub blocks self-approval,
so 1 would deadlock every merge. Real repos want 1+.

**`develop` is not protected, and the EC2 deploy has no approval gate.** Any
push to `develop` deploys straight to the demo server. The deploy job uses
`environment: demo-ec2`, which has no required reviewer yet — adding one is a
settings change only, no YAML.

The `github-pages` environment (with its required reviewer) is left over from
the Pages deploy and is no longer used by any job. The approval behaviour it
proved still applies once a reviewer goes on `demo-ec2`: the deploy job parks in
`waiting` until approved. Note `can_admins_bypass` defaults to **true** on an
environment — an admin can push a deploy through without the review. Set it
false if the approval must be unconditional.

### Proven, not assumed

PR #1 carried one deliberately wrong assertion. Result: `ci` **failed** in 11s,
`deploy` was **skipped** so nothing reached the live site, and the PR merge
state was **BLOCKED**. The gate stops a bad merge in practice, not just on paper.

## 5. Rolling this into TimberCore

Both jobs are close to copy-paste — point `ci` at `TimberCore/src/UI` and
`backend` at `TimberCore.sln`. Watch for:

- **`*.sln` in `.gitignore`.** The Vite template blanket-ignores it, so the
  solution file silently never reaches the repo and CI fails on `dotnet restore`
  with a missing-file error whose cause isn't obvious. Negated here with
  `!api/Demo.sln`.
- **The API holds file locks on its own DLLs.** Not an issue on a clean runner,
  but it's why local build order matters.
- **Credentials** are the one piece with an external dependency: an AWS IAM
  OIDC provider + deploy role (and SSM, or an S3 hand-off, instead of SSH) so
  the real pipelines hold no long-lived key. Needs whoever owns the AWS
  account — start it early.
- **Check the server OS's .NET packaging** before choosing framework-dependent
  vs self-contained publish (see [Why self-contained](#why-self-contained)).

## 6. Known gaps

- **Shared security group.** The demo instance uses `sg-018ed7306d4f32dc4`, the
  same group as `timbercore-prod-server` and `TimberCore-Staging-Server`, with
  22/80/443 open to `0.0.0.0/0`. Anything opened for the demo is opened on prod.
  Give the demo its own group; whether prod should keep 22 open to the world is
  for that group's owner.
- **No gate on `develop`** — see [Gates](#4-gates).
- **No HTTPS** — see [HTTPS](#https).
- **Host key trust-on-first-use** — see [Secrets](#3-secrets--credentials).
- **No rollback.** Each deploy overwrites the previous one in place; going back
  means reverting on `develop` and letting it redeploy.

## Commands

```bash
npm install
npm run dev                          # :5173
npm test
npm run build

dotnet test api/Demo.sln             # backend
```
