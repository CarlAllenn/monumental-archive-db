# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A single Docker image: official `postgres:18` (Debian trixie) plus exactly three extensions — PostGIS, pgaudit,
and edtf_postgres. There is no application code; the deliverables are the [Dockerfile](Dockerfile), the CI/publish
pipeline, and the supply-chain guarantees around them. Published as `ghcr.io/carlallenn/monumental-archive-db`;
consumers pin digests (no version tags — the image's "version" is the postgres major plus three extension pins).

## Commands

`mise install` bootstraps the pinned toolchain and git hooks (lefthook). All tooling is version-pinned via mise in
strict/locked mode — use the mise-provided tools, not system ones.

- `task ci` — the whole gate, identical locally and in CI: lints + trivy fs scan + edtf attestation check in
  parallel, then build → smoke → trivy image scan.
- `task build` — build `monumental-archive-db:candidate` for the local arch.
- `task smoke` — boot the candidate and prove extensions actually load (`scripts/db-image-smoke.sh`; asserts via
  `pg_get_loaded_modules()`, not `\dx`).
- `task lint` — all linters; individual ones are `task lint:yaml|toml|md|spell|ec|shell|actions|docker`.
- `task scan` / `task scan:image` / `task scan:edtf` / `task scan:secrets` — trivy fs, trivy image CVEs, edtf
  attestation, gitleaks history.

Lint tasks are checksum-fingerprinted (skip when inputs unchanged; `task --force` overrides). Scan tasks are
deliberately never fingerprinted — their inputs (vuln DBs, attestation state) change without commits.

## Architecture / invariants

- **Own the installation** ([docs/decisions/0001-own-the-installation.md](docs/decisions/0001-own-the-installation.md)):
  PostGIS/pgaudit are installed here from PGDG at our build time — never inherited from an image like
  `postgis/postgis` — so their OS dependencies resolve fresh from `trixie-security`. A weekly cache-free scheduled
  rebuild caps exposure at seven days.
- **edtf_postgres supply chain**: consumed as a prebuilt release artifact from `CarlAllenn/edtf` (nothing is
  compiled in this image). Its checksums in the Dockerfile are pinned per-arch, verified fail-closed by BuildKit's
  `ADD --checksum`, and deliberately NOT Renovate-tracked — `scripts/check-edtf-attestation.sh` proves in CI that
  the pinned hashes appear in the release's GitHub-attested SHA256SUMS. Both facts are needed; neither alone
  suffices. Never bump the edtf pin/checksums without keeping that gate green.
- **Renovate pin convention**: versions live in `ARG *_VERSION=` lines with a `# renovate:` comment above them —
  an inline version in an apt line would silently lose Renovate coverage. Policy canon lives in
  `CarlAllenn/renovate-config` (also the source of the lefthook remote config and Taskfile/trivy templates —
  marked "do not edit locally").
- **Baked server config**: `CMD` carries `shared_preload_libraries=pg_stat_statements,pgaudit` and
  `wal_level=logical` (ElectricSQL logical replication) so every consumer behaves identically.
  `/docker-entrypoint-initdb.d` is emptied (the consuming archive is migration-defined) and gosu is removed; the
  server starts directly as `USER postgres`.
- **Multi-arch without QEMU**: amd64 and arm64 each build, smoke, and scan on native runners
  (`.github/workflows/publish.yml`); after the manifest is pushed, the published bytes are pulled back by digest,
  re-proved, then cosign-signed keylessly with the publish workflow as identity.
- **Smoke-test trap**: the official entrypoint starts postgres twice on a fresh volume; the smoke script waits
  for the *second* "ready to accept connections" before asserting. Preserve that if touching
  `scripts/db-image-smoke.sh`.

## Enforcement layer

Git hooks (lefthook, installed by `mise install`, config partly pulled live from renovate-config) run the full
lint suite plus gitleaks and conventional-commit enforcement on every commit; pre-push builds and smokes the image
when the Dockerfile or smoke script changed. Fixing lint output is never optional. Personal overrides go in
`lefthook-local.yml` (gitignored).
