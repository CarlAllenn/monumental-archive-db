# Security policy

## Reporting a vulnerability

Report privately through GitHub's [security advisory
form](https://github.com/CarlAllenn/monumental-archive-db/security/advisories/new).
That keeps the report private until a fix ships and gives you credit on the
published advisory.

Please do not open a public issue for a suspected vulnerability.

If you cannot use GitHub advisories, email the maintainer address on the
commits in this repository.

## What to expect

An acknowledgement within **7 days**, and a triage verdict — accepted,
out of scope, or upstream — within **14 days**. Accepted defects in what
this repository controls are fixed and republished as a new digest; the
advisory is published with the fixing digest named in it.

## Scope, stated precisely

This repository assembles an image. It contains no application code, so
almost everything a vulnerability could be found in belongs to somebody
else — and saying which half is which is the only useful part of a scope
statement here.

**In scope** — defects in what this repository decides:

- The [Dockerfile](Dockerfile): what is installed, what is removed, what
  the runtime stage copies out of the build stage, and the baked `CMD`
  (`shared_preload_libraries`, `wal_level`).
- The published image's configuration: that it runs as `USER postgres`,
  that `/docker-entrypoint-initdb.d` is empty, that `gosu` is gone.
- The build and publish pipeline: the pins, the attestation gate in
  [scripts/check-edtf-attestation.sh](scripts/check-edtf-attestation.sh),
  the smoke test, and the signing identity.
- A pin this repository failed to update after a fix was available
  upstream.

**Out of scope** — report these to their own projects, though telling us
too is welcome and we will bump the pin:

- Vulnerabilities in PostgreSQL, PostGIS, pgaudit, or Debian packages.
  Report upstream; our remediation is a rebuild.
- Vulnerabilities in `edtf_postgres` itself — report to
  [CarlAllenn/edtf](https://github.com/CarlAllenn/edtf/security/advisories/new).
- How a consumer deploys the image: network exposure, `POSTGRES_PASSWORD`
  handling, volume permissions, TLS termination. The image ships no
  credentials and opens no ports by itself.

## Supported versions

**The latest published digest only.** This image has no version surface of
its own — its "version" is the postgres major plus three extension pins,
and its changes are pin bumps. There are no version tags and no
maintained back-branches: fixes land on `main` and a new digest publishes.

Consumers pin digests. That means a fix reaches you when you bump the
digest, which is what Renovate is for — `:main` exists so Renovate has
something to resolve against.

## The remediation model

The OS layer under PostGIS cannot be pinned by anyone: PostGIS's
transitive Debian dependencies resolve at build time. So remediation here
is **a scheduled cache-free rebuild**, weekly, which re-resolves that layer
fresh from `trixie-security` with every deliberate pin intact. Worst-case
exposure on a CVE in **the packages this image installs, and their
dependency closure** is therefore seven days from the fix landing in
Debian, without anyone filing anything.

Packages inherited from the base image have a different clock, and it is
worth being precise rather than claiming the shorter number for both.
`FROM postgres:18-trixie` is pinned by digest, so a cache-free rebuild
re-fetches those layers byte-for-byte identically — the weekly rebuild does
not move them. They move when the official image republishes and Renovate
bumps our base digest. That is usually quick, but it is a different
mechanism with a different failure mode: the weekly rebuild cannot silently
stall, whereas a base-digest bump can sit unmerged.

This distinction is narrower than it sounds, because the packages that
motivated the whole design are on the seven-day clock. `libexpat1` and
`libnss3` — the ones that were once frozen at versions carrying 22 CVEs —
are absent from the base and installed here, precisely so that they are
ours to refresh.

The reasoning is
[docs/decisions/0001-own-the-installation.md](docs/decisions/0001-own-the-installation.md);
that decision is the reason PostGIS and pgaudit are installed here from
PGDG rather than inherited from an upstream image whose apt layer we could
not refresh.

The CVE gate itself lives on pull requests, never on the publish path — a
CVE published tomorrow must not retroactively kill a publish, and the
weekly remediation rebuild especially must not die because a scanner had a
bad day. Publish runs scan report-only, so every published digest has its
scan state on the run log.

## Verifying what you pulled

Every manifest is cosign-signed keylessly, with this repository's publish
workflow as the certificate identity:

```sh
cosign verify ghcr.io/carlallenn/monumental-archive-db@<digest> \
  --certificate-identity-regexp \
    '^https://github.com/CarlAllenn/monumental-archive-db/\.github/workflows/publish\.yml@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

A signature that does not verify against that identity is not ours,
whatever the tag says. The image also carries SPDX SBOM and provenance
attestations from the build.
