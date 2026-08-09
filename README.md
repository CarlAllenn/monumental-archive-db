# monumental-archive-db

[![ci](https://github.com/CarlAllenn/monumental-archive-db/actions/workflows/ci.yml/badge.svg)](https://github.com/CarlAllenn/monumental-archive-db/actions/workflows/ci.yml)
[![publish](https://github.com/CarlAllenn/monumental-archive-db/actions/workflows/publish.yml/badge.svg)](https://github.com/CarlAllenn/monumental-archive-db/actions/workflows/publish.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/CarlAllenn/monumental-archive-db/badge)](https://scorecard.dev/viewer/?uri=github.com/CarlAllenn/monumental-archive-db)
[![license](https://img.shields.io/badge/license-AGPL--3.0--only-blue.svg)](LICENSE)

The [Monumental Archive](https://github.com/CarlAllenn)'s PostgreSQL
image: official `postgres:18` (Debian trixie) plus exactly three audited
extensions — [PostGIS](https://postgis.net/),
[pgaudit](https://github.com/pgaudit/pgaudit), and
[edtf_postgres](https://github.com/CarlAllenn/edtf) (native EDTF
validation from the same `edtf-core` the archive's web layer runs as
WASM, so the two can never diverge).

```text
ghcr.io/carlallenn/monumental-archive-db
```

## What the image asserts

- **Multi-architecture for real.** amd64 and arm64 are each built on
  native hardware — no QEMU, ever. A green build proves the image on the
  machine that will run it.
- **Tested before published.** Every architecture boots and proves its
  extensions actually load (`pg_get_loaded_modules()`, not `\dx`) before
  anything is pushed; after the manifest exists, the published bytes are
  pulled back by digest and proved again before signing.
- **Signed.** The manifest is cosign-signed keylessly; the certificate
  identity is this repository's publish workflow *on `main`*, and nothing
  weaker — the ref is part of the pattern, so a signature minted from any
  other ref does not verify:

  ```sh
  cosign verify ghcr.io/carlallenn/monumental-archive-db@<digest> \
    --certificate-identity-regexp \
      '^https://github.com/CarlAllenn/monumental-archive-db/\.github/workflows/publish\.yml@refs/heads/main$' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
  ```

- **Rebuilt weekly, cache-free.** PostGIS's transitive OS dependencies
  can be pinned by nobody; a scheduled `--no-cache` rebuild resolves them
  fresh from `trixie-security`, capping exposure on that layer at seven
  days with every deliberate pin intact. The reasoning is
  [docs/decisions/0001-own-the-installation.md](docs/decisions/0001-own-the-installation.md).

## Tags

`:main` floats with the latest publish; `:sha-<commit>` is per-commit
traceability. **Consumers pin the digest** — the tags exist so Renovate
has something to resolve digest updates against. There are no version
tags: this image has no version surface of its own; its "version" is the
postgres major plus three extension pins, and its changes are pin bumps.

## Baked-in server configuration

`shared_preload_libraries=pg_stat_statements,pgaudit` and
`wal_level=logical` ride the image `CMD`, so every consumer — compose
stacks, throwaway schema-tooling containers, production — behaves
identically. `/docker-entrypoint-initdb.d` is emptied (the consuming
archive is migration-defined) and the server starts as `USER postgres`
directly (`gosu` is removed as dead code).

## Development

`mise install` bootstraps the pinned toolchain and git hooks; `task ci`
is the whole gate, identical locally and in CI — lints, trivy fs scan,
the edtf attestation check, then build, smoke, and the canonical trivy
image gate (all severities, `--ignore-unfixed`). Policy canon lives in
[CarlAllenn/renovate-config](https://github.com/CarlAllenn/renovate-config).

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) (how to
contribute, the enforced coding standard, DCO),
[GOVERNANCE.md](GOVERNANCE.md) (decision-making and continuity), the
[roadmap](docs/roadmap.md), the [security policy](SECURITY.md) and the
[security assurance case](docs/assurance-case.md).
