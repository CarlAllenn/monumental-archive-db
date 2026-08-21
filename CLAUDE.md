# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.

## What this repo is

A single Docker image: official `postgres:18` (Debian trixie) plus
exactly three extensions — PostGIS, pgaudit, and edtf_postgres. There is
no application code; the deliverables are the [Dockerfile](Dockerfile),
the smoke test, and the supply-chain guarantees around them. It has no
version surface — no tags, no releases — which is why it is the org's
first member of the **continuous archetype**: the artifact's "version"
is its pin set, and a change is a pin bump.

This repository joined `monumental-archive` on 2026-08-21
(`.github#670`). The governance, the toolchain and the publish machinery
all live in
[monumental-archive/.github](https://github.com/monumental-archive/.github)
— the canon. Its docs are the authority; nothing here restates a rule
the canon owns.

## Commands

The org toolbelt is the whole toolchain, delivered from the canon at the
SHA `.github/workflows/ci.yml` pins.

- `mise trust && mise install && mise run hooks:install` — once per
  clone.
- `mise run ci` — the whole gate, identical locally and in CI (belt
  linters over tracked files, then whatever repo tasks exist; this repo
  defines none).
- `mise run fix` — the write-mode siblings the gate deliberately
  excludes.
- `docker build --tag monumental-archive-db:candidate .` then
  `bash scripts/db-image-smoke.sh monumental-archive-db:candidate` —
  build and prove an image by hand. Not gate work: the publish path
  builds, smokes and signs the bytes it published, so a gate build would
  prove something about bytes nobody ships.

Nothing is pinned or configured here that the belt already delivers.
`mise.toml` carries no tools and no tasks on purpose; if a task is ever
added it needs `[task_config] shell = "bash -euo pipefail -c"` beside it
(`.github#700`).

## Architecture / invariants

- **Own the installation**
  ([0001](docs/decisions/0001-own-the-installation.md)): PostGIS and
  pgaudit are installed here from PGDG at our build time — never
  inherited from an image like `postgis/postgis` — so their OS
  dependencies resolve fresh from `trixie-security`. A weekly cache-free
  scheduled rebuild caps exposure at seven days.
- **edtf_postgres supply chain**: consumed as an OCI image pinned by
  manifest-index digest (nothing is compiled in this image). That image
  is *postgres:18-trixie plus the extension*, so it is a **build stage
  only** — `FROM`-ing it as our base would inherit an apt layer we
  cannot refresh and break "own the installation" above. The runtime
  stage globs `edtf_postgres*` out of the two extension paths rather
  than copying the extension directory wholesale, so none of its base
  files cross over. The digest is fail-closed in BuildKit. Proving the
  bytes are the *right* bytes — an attestation over that digest naming
  edtf's publish workflow — is the canon's base-approval machinery; the
  hand-rolled gate this repo used to carry was deleted at the import,
  and the canon's walk being pgrx-scoped is filed as `.github#715`.
- **The `FROM` line is the import's one known leftover.** It still names
  the pre-transfer publisher because an image published before the
  transfer cannot carry an org-identity attestation. It is repinned to
  the org path, at the digest of edtf's first org-path release, in the
  follow-up PR (#5, `.github#669`), which also wires the continuous
  publish stub. `scripts/db-image-smoke.sh` parses that same `FROM` line
  for the expected extension version, so the two move together.
- **Renovate pin convention**: apt versions live in `ARG *_VERSION=`
  lines with a `# renovate:` comment above them — an inline version in
  an apt line would silently lose Renovate coverage. Image pins need
  none of that: the native Dockerfile manager reads `FROM` lines and
  bumps tag and digest together. `renovate.json` extends the org preset
  by tag; the two rules it keeps are repo identity (this image's package
  names, and the postgres major decision), and Renovate merges them with
  the preset's rather than replacing them.
- **Baked server config**: `CMD` carries
  `shared_preload_libraries=pg_stat_statements,pgaudit` and
  `wal_level=logical` (ElectricSQL logical replication) so every
  consumer behaves identically. `/docker-entrypoint-initdb.d` is emptied
  (the consuming archive is migration-defined) and gosu is removed; the
  server starts directly as the postgres user, declared numerically
  (`USER 999`) so an orchestrator enforcing runAsNonRoot can verify it.
- **Multi-arch without QEMU**: amd64 and arm64 each build and smoke on
  native runners. That property belongs to the org's shared image build,
  which this repository calls once the continuous stub lands.
- **Smoke-test trap**: the official entrypoint starts postgres twice on
  a fresh volume; the smoke script waits for the *second* "ready to
  accept connections" before asserting. Preserve that if touching
  `scripts/db-image-smoke.sh`.

## Enforcement layer

Git hooks come from the canon by remote (`lefthook.yml` pins a canon
tag): typos and actionlint at pre-commit, the commit canon and the DCO
sign-off at commit-msg, `mise run ci` at pre-push. Commits are
conventional, imperative, lowercase, 72 columns, signed off; the PR
title becomes the squash subject and is held to the same rules. Fixing
lint output is never optional — the belt runs at maximum enforcement and
the repo conforms to the tools, never the reverse. Personal overrides go
in `lefthook-local.yml` (gitignored).
