# Security assurance case

Why this project's security requirements are met: the threat model, the
trust boundaries, the design argument, and the argument that common
implementation weaknesses are countered. The security requirements
themselves — what a user can and cannot expect — are stated in
[SECURITY.md](../SECURITY.md); this document is the evidence that they
hold.

The unusual thing about this project is that it contains no application
code. It is an *assembly*: a Dockerfile, three extension pins, and a
pipeline that proves what it publishes. So the entire attack surface worth
arguing about is the supply chain, and this document spends its length
there rather than on input handling that does not exist here.

## Threat model

In rough order of exposure.

**Supply-chain substitution — the primary threat.** A consumer runs
whatever bytes they pull. An attacker who can change what `docker pull`
returns, or what our build ingests, owns every database built from it.
Four distinct substitution points:

1. *The base image.* `postgres:18-trixie` is a mutable tag; whoever
   controls that tag controls our base.
2. *The extension build stage.* `edtf-postgres` is published by a related
   but separate repository, with its own compromise surface.
3. *The apt layer.* PostGIS and pgaudit come from PGDG at our build time.
4. *The published manifest.* An attacker with registry write could push a
   different image under our tag.

**CI compromise.** The publish workflow can push to GHCR and holds a
Sigstore OIDC identity. A workflow that can be induced to build something
other than the reviewed tree, or to sign something it did not prove, is
equivalent to registry compromise — and *more* dangerous, because the
result would carry a valid signature.

**Known-vulnerable OS packages.** PostGIS drags in the GDAL stack, and
with it libraries (libexpat1, libnss3) with a steady CVE cadence. This is
not a hypothetical: the decision record
([0001](decisions/0001-own-the-installation.md)) exists because
`postgis/postgis` once froze exactly those two packages at versions
carrying 22 CVEs that no rebuild of ours could refresh.

**Configuration that misleads a consumer.** The image bakes
`shared_preload_libraries` and `wal_level=logical` into `CMD`. If a
consumer believes pgaudit is loaded and it is not, they lose their audit
trail without any error — a silent failure of a security control.

### Explicitly out of scope

- **What the consumer does with the database.** Network exposure,
  `POSTGRES_PASSWORD` handling, TLS termination, volume permissions, and
  role design are deployment decisions. The image ships no credentials and
  publishes no ports by itself.
- **Vulnerabilities in PostgreSQL, PostGIS, pgaudit, or Debian.** In scope
  is *failing to ship the fix*; the defect itself belongs upstream.
- **Volume denial of service.** A database can be overwhelmed by load;
  nothing in an image can prevent that.
- **Confidentiality of the image contents.** Everything here is public by
  construction. There is nothing secret in the image, and the build
  deliberately embeds its full non-secret input set in the provenance
  attestation.

## Trust boundaries

- **The publish boundary — what CI builds versus what a consumer pulls.**
  This is the boundary that matters most, and the pipeline is arranged so
  that nothing is trusted across it without re-proof: build → smoke →
  push → **pull the published bytes back by digest and prove them again**
  → sign → verify the signature the way a stranger would. The signature
  therefore asserts something demonstrated *of the bytes a consumer gets*,
  not of a local twin that was never published.
- **The build-stage boundary.** `edtf-postgres` is a separate trust domain.
  It is crossed by exactly two `COPY --from` globs
  ([Dockerfile:71-72](../Dockerfile#L71-L72)) — the `.so` and the
  `edtf_postgres*` control/SQL files — rather than by `FROM`, and
  deliberately not by copying the extension directory wholesale, because
  that directory also holds *its* base image's control files. The narrow
  glob is the boundary enforcement.
- **The apt boundary.** PGDG and Debian archives are trusted for package
  contents, authenticated by apt's own repository signing, and pinned to
  exact versions under the Renovate convention.
- **The privilege boundary inside the image.** The server runs as `USER
  postgres`; there is no root phase and no setuid path to one, because
  `gosu` — whose only purpose is root→postgres descent — is deleted.
- **The registry identity boundary.** Consumers distinguish our images from
  anyone else's by cosign verification against this repository's publish
  workflow, not by the tag.

## Secure design principles

- **Economy of mechanism.** The deliverable is ~95 lines of Dockerfile and
  a smoke script. There is no application code, no init scripts, no
  entrypoint of our own, no seed data. Most classes of defect are absent
  because the code that would contain them was never written.
- **Fail-safe defaults.** Every trust decision is fail-closed by
  construction rather than by checking. Both `FROM`s are digest-pinned, and
  BuildKit refuses to proceed on mismatch — a substituted base does not
  produce a warning, it produces a failed build. The apt versions are exact
  pins, so a missing version fails the install rather than silently
  resolving to something newer. The image starts non-root by default, and
  cannot be talked into root because the tool for it is gone.
- **Complete mediation.** There is exactly one path by which an image is
  produced and exactly one identity that can sign one. No manual publish
  path exists, `task ci` in a shell and the CI gate run the same tasks in
  the same order, and the publish workflow carries no cache of any kind so
  there is no second, unreviewed source of layer content.
- **Defence in depth on the extension pin, deliberately doubled.** The
  digest proves the bytes did not change; the attestation check
  ([scripts/check-edtf-attestation.sh](../scripts/check-edtf-attestation.sh))
  proves the *same* digest carries GitHub-attested provenance naming edtf's
  publish workflow — that they are the *right* bytes. Neither alone
  suffices: a digest pins whatever it was first set to, including something
  wrong; an attestation without a digest pin does not say which bytes ship.
- **Least privilege.** Workflows default to `contents: read`, with
  additional scopes granted per job and annotated inline with why (`packages:
  write` only on the pushing jobs, `id-token: write` only where Sigstore
  needs it). Runners enforce `egress-policy: block` with allowlists derived
  from audit runs rather than guessed. No long-lived registry or signing
  credential exists to leak — GHCR uses the run's own token and signing is
  keyless.

## Common implementation weaknesses, countered

| Weakness class | Countermeasure | Evidence |
| --- | --- | --- |
| Memory safety, injection, logic defects in our own code | There is no application code. The only executable content authored here is two shell scripts, which handle no untrusted input. | [Dockerfile](../Dockerfile), [scripts/](../scripts/) |
| Known-vulnerable OS packages | Own the installation, then rebuild on a clock: a weekly `--no-cache` rebuild re-resolves the unpinnable layer from `trixie-security`, capping exposure at seven days. | [0001](decisions/0001-own-the-installation.md), `.github/workflows/publish.yml` |
| Known-vulnerable dependencies, undetected | trivy at all severities with `--ignore-unfixed`, over both the filesystem and the built image, on every pull request. Deliberately never fingerprinted — the vulnerability DB changes without commits, so a cached "unchanged inputs" skip would be a false pass. | `task scan`, `task scan:image`, [trivy.yaml](../trivy.yaml) |
| Dependency drift and stale pins | Renovate, with the pin convention enforced by the `ARG *_VERSION=` + `# renovate:` pairing so a pin cannot silently lose coverage. | [renovate.json](../renovate.json) |
| Supply-chain substitution | Digest pinning on both `FROM`s (fail-closed in BuildKit), the attestation gate on the extension image, and cosign keyless signing of the published manifest with the workflow as identity. | Dockerfile, `scripts/check-edtf-attestation.sh` |
| Publishing something that was never proved | The publish invariant: build and smoke before any push; after the manifest exists, pull it back by digest and re-prove; sign last and only on proof; then verify as a consumer would. | `.github/workflows/publish.yml` |
| A signature that succeeds but does not verify | The pipeline runs `cosign verify` against the exact identity consumers pin, immediately after signing. A signing step that exits 0 is not a signature that verifies. | `.github/workflows/publish.yml` |
| Silent loss of a security control | The smoke test asserts against `pg_get_loaded_modules()`, not `\dx`. `\dx` reports what is *installable*; only the former proves pgaudit is actually loaded. | [scripts/db-image-smoke.sh](../scripts/db-image-smoke.sh) |
| Vulnerable or malformed CI workflows | actionlint plus zizmor at `--persona=pedantic` on every commit and in CI; the six online audits (typosquat, impostor-commit, stale refs) run weekly. CodeQL analyses the workflows as its `actions` language. | `.github/workflows/` |
| Unpinned CI actions | Every `uses:` is pinned to a full commit SHA with the version in a trailing comment. | `.github/workflows/` |
| Credential leakage | gitleaks runs on every commit and over full history in CI; `persist-credentials: false` on every checkout; no long-lived publishing secret exists. | `task scan:secrets`, lefthook |
| Dockerfile antipatterns | hadolint on every commit and in CI. | [.hadolint.yaml](../.hadolint.yaml) |

## Why this is believed sufficient

The residual risks, named honestly:

- **A compromise of the `edtf-postgres` publishing repository** would
  produce a correctly-attested malicious extension, and both of our gates
  would pass. This is a real transitive trust relationship, mitigated only
  by that repository running the same hardening as this one and by the
  narrowness of what crosses the boundary — two globbed paths, not a base
  image. It is the strongest argument for keeping that boundary a `COPY`
  and never a `FROM`.
- **A seven-day window on OS-layer CVEs.** The weekly rebuild is a
  deliberate trade: a daily rebuild would republish digests faster than
  consumers could reasonably track, and a rebuild triggered by advisory
  feeds would make the publish path depend on a scanner having a good day.
  Seven days is the stated commitment, not an accident, and any consumer
  needing tighter can rebuild from this repository themselves.
- **Three Scorecard checks and the Best Practices gold badge are
  structurally unreachable** for a single maintainer: Code-Review,
  Contributors, and non-author review. These are head-count facts, not
  hygiene gaps. The mitigation is [GOVERNANCE.md](../GOVERNANCE.md)'s
  access-continuity section rather than a pretence that a second reviewer
  exists.

Both residual risks fail toward *detectability* rather than silence, which
is the property the design is actually organised around. A substituted
base fails the build rather than shipping. A wrong extension digest fails
the build. A signature over unproved bytes cannot be produced, because
signing happens after the re-proof step and nowhere else. An unloaded
pgaudit fails the smoke test rather than producing a database that quietly
audits nothing. The one thing this design consciously accepts — a
vulnerable OS package during the rebuild window — is public in the trivy
output of every run, rather than hidden.
