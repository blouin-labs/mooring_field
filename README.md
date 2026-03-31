# mooring_field

Version control and CI/CD for Docker Compose stacks deployed on [harbor_srv](https://github.com/blouin-labs/harbor_srv).

## Directory layout

```
stacks/
  {project-name}/
    compose.yaml
    .env.example    ← commit this; actual .env is gitignored
    ...             ← any other config files (no databases or runtime data)
```

Each subdirectory under `stacks/` is one project. A stack may contain a `Dockerfile` (if a
custom image is needed) alongside the compose file.

Subdirectory names use numeric prefixes to control startup ordering (e.g. `05-technitium`,
`10-vpn_standalone`).

## Branch model

| Branch | Purpose |
|--------|---------|
| `staging` | Default. All PRs target here. |
| `main` | Production. Promoted from `staging` via the Promotion workflow only. |

Feature branches use the prefixes `feat/`, `fix/`, `docs/`, `chore/`.

## CI/CD flow

```
PR → staging       check.yml     compose-validate + hadolint + actionlint + vale
push → staging     build.yml     build custom images → ghcr.io :{sha} + :staging
Promotion          promotion.yml fast-forward main + re-tag + rsync stacks + compose up
```

1. Open a PR targeting `staging` — `check.yml` validates compose files and Dockerfiles.
2. PR merges to `staging` — `build.yml` builds any custom images (stacks with a `Dockerfile`)
   and pushes `:sha` and `:staging` tags to `ghcr.io/blouin-labs/{service}`.
3. Run the **Promotion** workflow (`promote-and-deploy`) — verifies staging CI is green,
   fast-forwards `main`, re-tags images `:staging` → `:latest`, rsyncs stack files to harbor_srv,
   then runs `docker compose up -d` for each stack.

For an emergency re-deploy without promoting `main`, use the `deploy` action.

## Secrets

- `.env` files are **gitignored**. Commit `.env.example` with placeholder values only.
- The actual `.env` files must be placed on the server manually (or will eventually be injected
  from GitHub Actions secrets).

## Issues

Issues live in [blouin-labs/issues](https://github.com/blouin-labs/issues) with the `mooring_field` label.
# probe
