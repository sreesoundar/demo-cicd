# demo-cicd

Throwaway app used to prove out a GitHub Actions CI/CD pipeline before rolling
the same shape into the real TimberCore repos. ClickUp: 14yp17zn2mr.

- Repo: https://github.com/sreesoundar/demo-cicd (public)
- Live: https://sreesoundar.github.io/demo-cicd/
- Local: `C:\SREE\dev\demo-cicd`

No TimberCore code, no credentials, nothing pointing at staging or prod.

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
- `pull_request` → `main`: runs `ci` and `backend`.
- `push` → `main`: runs `ci` and `backend`, then `deploy`.
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

`cache: true` on `setup-dotnet` is deliberately **not** used: it requires
`packages.lock.json` files, which means committing to lock-file maintenance via
`RestorePackagesWithLockFile`. Restore is seconds on two small projects. For
TimberCore's larger solution it's worth revisiting, with that cost understood.

### Deploy (`deploy` job)
Target: **GitHub Pages**, https://sreesoundar.github.io/demo-cicd/

- `ci` uploads `dist/` via `actions/upload-pages-artifact`, gated on
  `github.ref == 'refs/heads/main'` so PR runs build-and-verify without
  publishing anything.
- `deploy` `needs: [ci, backend]` — either half failing blocks the release.
- `actions/deploy-pages` publishes that artifact.
- `vite.config.ts` sets `base: '/demo-cicd/'` — without it the built asset URLs
  resolve to the domain root and the Pages site loads blank.

Pages was chosen as the demo target because it needs zero cloud infrastructure
and zero long-lived credentials. For the real apps this job is the seam to
swap: same gates, different deploy action (AWS/ECS/S3/Lambda).

**Known gap:** the `backend` job builds and tests but nothing deploys it. Pages
is static-frontend-only. A real backend deploy is the AWS work below.

Runners are pinned to `ubuntu-24.04` rather than `ubuntu-latest`, which migrates
to Ubuntu 26 on 19 Oct 2026.

## 3. Secrets / credentials

**None in this pipeline** — Pages authenticates via OIDC, not a stored token:

```yaml
permissions:
  pages: write
  id-token: write
```

The job mints a short-lived token per run. Nothing to rotate, nothing to leak.

For the real pipelines, use the same mechanism rather than long-lived keys:
configure an AWS IAM OIDC provider trusting GitHub, and have the deploy job
assume a role via `aws-actions/configure-aws-credentials`. Fall back to
`secrets.*` (repo or environment secrets) only for third-party services that
can't do OIDC. Note the frontend rule still applies — a `VITE_*` value injected
at build time is inlined into the public bundle, so it is config, never a secret.

Default token permissions are pinned to `contents: read` at workflow level, with
write scopes granted only on the one job that needs them.

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

`environment: github-pages` is attached to the deploy job — that's the hook for
required reviewers (**Settings → Environments**) to make prod deploys
manual-approval. Not enabled on the demo; this is where it goes for real.

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
- **Deploy target** is the one piece that's genuinely new work: AWS IAM OIDC
  provider + deploy role, so the real pipelines stay secret-free the same way
  this one does.

## Commands

```bash
npm install
npm run dev                          # :5173
npm test
npm run build

dotnet test api/Demo.sln             # backend
```
