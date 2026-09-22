# demo-cicd

Throwaway app used to prove out a GitHub Actions CI/CD pipeline before rolling
the same shape into the real TimberCore repos. ClickUp: 14yp17zn2mr.

## 1. Demo app

Vite + React 19 + TypeScript (`npm create vite@latest -- --template react-ts`),
deliberately the same stack as `TimberCore/src/UI` so the workflow transfers
one-for-one. Added on top of the template: `vitest`, one pure util
(`src/greet.ts`) and its test (`src/greet.test.ts`) so the CI test step has
something real to fail on.

- Repo: https://github.com/sreesoundar/demo-cicd (public)
- Live: https://sreesoundar.github.io/demo-cicd/
- Local: `C:\SREE\dev\demo-cicd`

No TimberCore code, no credentials, nothing pointing at staging or prod.

## 2. Pipeline

One workflow file: `.github/workflows/ci-cd.yml`.

### Triggers
- `pull_request` → `main`: runs the `ci` job only.
- `push` → `main`: runs `ci`, then `deploy`.
- `concurrency` cancels a superseded run on the same ref, so a fast follow-up
  push doesn't race the earlier deploy.

### Build steps (`ci` job)
1. `actions/checkout`
2. `actions/setup-node` @ Node 20 with `cache: npm` (restores `~/.npm` keyed on
   `package-lock.json` — turns a ~60s install into a few seconds)
3. `npm ci` — lockfile-exact install, fails if `package.json` and the lockfile
   have drifted apart (`npm install` would silently fix it up instead)
4. `npm run lint` — oxlint
5. `npm run build` — `tsc -b && vite build`, so a type error fails CI

### Test step
`npm test` → `vitest run` (single run, not watch — watch mode never exits and
would hang the runner).

### Deploy (`deploy` job)
Target: **GitHub Pages**, https://sreesoundar.github.io/demo-cicd/.

- `ci` uploads `dist/` via `actions/upload-pages-artifact`, gated on
  `github.ref == 'refs/heads/main'` so PR runs build-and-verify without
  publishing anything.
- `deploy` `needs: ci`, so a red test blocks the deploy.
- `actions/deploy-pages` publishes that artifact.
- `vite.config.ts` sets `base: '/demo-cicd/'` — without it the built asset URLs
  resolve to the domain root and the Pages site loads blank.

Pages was chosen as the demo target because it needs zero cloud infrastructure
and zero long-lived credentials. For the real apps this job is the seam to
swap: same gates, different deploy action (AWS/ECS/S3/Lambda).

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

- `deploy` runs only on `main`, and only after `ci` passes.
- `environment: github-pages` — attaching an environment means a required
  reviewer can be added in **Settings → Environments** to make prod deploys
  manual-approval. Not enabled on the demo; this is where it goes for real.
- **Branch protection on `main`** (Settings → Branches → Add rule) to make it
  stick: require a PR before merging, and mark the `ci` check required. Without
  this, Actions reports failures but nothing stops a merge.

## 5. Rolling this into TimberCore

The frontend job is a near copy-paste (`TimberCore/src/UI` working-directory).
The backend needs a parallel job: `actions/setup-dotnet`, `dotnet restore`,
`dotnet build TimberCore.sln`, `dotnet test TimberCore.sln`. Mind the existing
constraint that the API holds file locks on its own DLLs — not an issue on a
clean runner, but it is why local build order matters.

## Commands

```bash
npm install
npm run dev     # :5173
npm test
npm run build
```
