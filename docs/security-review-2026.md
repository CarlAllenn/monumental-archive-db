# Security review — 2026

A dated review of this project's security posture, distinct from
[the assurance case](assurance-case.md). The assurance case is a standing
argument, maintained continuously and written to be true at all times. This
document is the opposite: a snapshot of one deliberate pass over the
security boundary on a particular day, including the things that pass found
wrong.

- **Date:** 2026-08-09
- **Reviewer:** Carl Allen (maintainer), with tool assistance
- **Commit reviewed:** `8f4b0fe`
- **Previous review:** none — this is the first

## Scope

The security requirements under review are the ones stated in
[SECURITY.md](../SECURITY.md), and the boundary is the one drawn in
[the assurance case](assurance-case.md#trust-boundaries). Concretely, this
pass covered:

- [`Dockerfile`](../Dockerfile) — what is installed, what is removed, what
  crosses the build-stage boundary, and the baked `CMD`.
- [`scripts/check-edtf-attestation.sh`](../scripts/check-edtf-attestation.sh)
  — the upstream supply-chain gate.
- [`scripts/db-image-smoke.sh`](../scripts/db-image-smoke.sh) — the test
  that a security control (pgaudit) is actually loaded.
- `.github/workflows/publish.yml` — the publish ordering invariant, the
  signing identity, and token scopes.
- `.github/workflows/ci.yml` and `scheduled.yml` — runner hardening and
  egress policy.
- The three repository rulesets, and the remediation model's actual
  mechanics as opposed to its documented claim.

Deliberately **not** covered, because they belong to other projects and
this project's remediation for all of them is a pin bump: defects inside
PostgreSQL, PostGIS, pgaudit, `edtf_postgres` or Debian packages.

## Method

Manual reading of the whole security-relevant surface — it is small enough
that sampling would have been a choice rather than a necessity — plus
direct verification of live claims where the claim was checkable rather
than merely readable. Specifically, the response headers of the project
site were fetched and inspected rather than assumed, and the mechanics of
the weekly rebuild were traced through `no-cache` and the digest pins
rather than taken from the prose describing them.

The design question driving the pass was the one that matters for this kind
of repository: **where does the project trust something it has not
proved, and does the documentation claim more than the mechanism
delivers?** Two of the findings below come from that second half.

## Findings

### F-1 — The upstream attestation gate is not ref-anchored (moderate)

`scripts/check-edtf-attestation.sh` verifies the pinned `edtf-postgres`
digest with:

```sh
gh attestation verify "oci://${image}" --repo "${repo}" \
  --signer-workflow "CarlAllenn/edtf/.github/workflows/publish.yml"
```

`--signer-workflow` constrains the certificate identity to that workflow
*path*, with no constraint on the ref it ran from. An attestation produced
by edtf's `publish.yml` running on **any** branch or tag therefore
satisfies this gate.

This is precisely the weakness the project already identified and fixed on
its own side. The cosign verification in `publish.yml` originally ended its
identity pattern at `publish\.yml@`, and was deliberately anchored through
`@refs/heads/main$` because, in that workflow's own words, ending it
earlier "would accept this workflow run from ANY ref, so a branch or tag
someone could push would mint signatures indistinguishable from ours." The
same reasoning applies unchanged to the upstream attestation, and was not
carried across.

Exploitation requires push access to `CarlAllenn/edtf`, which today is the
same maintainer — so the practical risk is low and the finding is about
defence in depth rather than an open door. But defence in depth is the
stated justification for this gate existing at all: the assurance case
argues the digest and the attestation are both needed because neither alone
suffices. A gate that accepts any ref is weaker than the argument claims.

**Disposition:** fix. Replace or supplement `--signer-workflow` with
`--cert-identity-regexp` anchored through `@refs/heads/main$`, mirroring
the cosign pattern exactly. Tracked as its own issue; the fix is small but
touches a security-critical gate, so it lands with CI proving the gate
still passes against the real attestation and still fails closed.

### F-2 — The seven-day remediation claim is broader than the mechanism (low)

[SECURITY.md](../SECURITY.md) states that worst-case exposure on an
OS-layer CVE is seven days, on the strength of the weekly cache-free
rebuild. Tracing the mechanism:

- `publish.yml` sets `no-cache: ${{ github.event_name == 'schedule' }}`, so
  the weekly run does rebuild every layer it builds.
- But `FROM postgres:18-trixie@sha256:3a82e1…` is **digest-pinned**. A
  cache-free rebuild re-fetches those base layers by digest and therefore
  gets byte-identical content.

So the weekly rebuild refreshes the packages this image installs and their
dependency closure — which is where the motivating CVEs lived, since
[0001](decisions/0001-own-the-installation.md) is explicit that `libexpat1`
and `libnss3` are "absent from the base, installed here." It does **not**
refresh packages already present in the base image at the pinned digest.
Those move only when Renovate bumps the base digest and that bump merges.

The claim is therefore correct for the case it was written about and
overbroad as stated. This is a documentation-accuracy finding, not a design
defect: the actual exposure for base-image packages is the upstream
`postgres:18-trixie` republish cadence plus Renovate's, which in practice
is short, but it is a different mechanism with a different failure mode —
notably, it can stall silently if a Renovate PR sits unmerged, whereas the
weekly rebuild cannot.

**Disposition:** scope the wording in SECURITY.md to distinguish the two
layers and name the base-digest bump as the second remediation path.
Deliberately *not* a change to the design.

### F-3 — Runner egress allowlists are inherited, not derived (low, already tracked)

The `harden-runner` allowlists in the Scorecard and CodeQL jobs were copied
from a sibling repository rather than derived from this repository's own
audit runs, which the job comments say outright. The CI job's list includes
`pypi.org`, `files.pythonhosted.org` and `nodejs.org`, none of which are
obviously required by this repository's toolchain.

Impact is bounded: these jobs hold `contents: read` against a public
repository, so over-broad egress is an exfiltration surface with nothing
confidential behind it. It is nonetheless the opposite of the stated
principle that allowlists are "derived from audit runs rather than
guessed."

**Disposition:** already tracked as
[#12](https://github.com/CarlAllenn/monumental-archive-db/issues/12), with
the correct rule recorded there — re-derive from a live run; do not prune
by inspection.

### F-4 — apt traffic is authenticated but not encrypted (informational, accepted)

The CI egress allowlist permits `deb.debian.org:80` and
`apt.postgresql.org:80`. Package integrity rests on apt's repository
signatures rather than on transport security, which is Debian's own
position and standard practice; the cost is that an on-path observer learns
which packages are being fetched.

**Disposition:** accepted, no action. Forcing HTTPS would require
overriding the base image's sources configuration for a confidentiality
property that does not matter for a public build of a public image.

### F-5 — Digest extraction takes the first match only (informational)

`check-edtf-attestation.sh` pipes its `sed` match through `head -1`, so if
the Dockerfile ever contained two `edtf-postgres … AS edtf` lines, only the
first would be verified. BuildKit would reject a duplicate stage name
before this mattered, so the condition is currently unreachable.

**Disposition:** no action. Recorded so a future reader does not mistake it
for an oversight.

## Verified sound

Things this pass specifically tried to break and could not:

- **The publish ordering invariant holds.** Build → smoke → push → pull the
  published bytes back by digest → re-prove → sign → verify as a stranger
  would. There is no path that signs anything unproved, because signing
  happens after the re-proof step and nowhere else.
- **The signing identity is correctly anchored.** The cosign
  `--certificate-identity-regexp` is anchored through `@refs/heads/main$`,
  and the same string appears in README.md and SECURITY.md, so a consumer
  pinning it and the pipeline asserting it cannot drift apart silently.
- **The build-stage boundary is narrow and correct.** Two globbed `COPY
  --from` paths, not a `FROM` and not a wholesale directory copy — so the
  edtf image's own base control files cannot displace ours.
- **The privilege boundary is real, not declared.** `gosu` is deleted
  rather than merely unused, so there is no setuid path from `postgres`
  back to root, and `/docker-entrypoint-initdb.d` is emptied.
- **No long-lived credential exists to leak.** GHCR authenticates with the
  run's own token, signing is keyless, and every checkout sets
  `persist-credentials: false`. There is nothing in repository secrets a
  successor would need handed over.
- **The site hardening headers are present.** Verified against live
  responses: HSTS with `includeSubdomains; preload`, a `default-src 'none'`
  CSP with `frame-ancestors 'none'`, `x-frame-options: deny`,
  `x-content-type-options: nosniff`, and a referrer policy.
- **The smoke test asserts the security control, not its availability.**
  `pg_get_loaded_modules()` rather than `\dx`, so an unloaded pgaudit fails
  the gate instead of producing a database that quietly audits nothing.

## Residual risks

Unchanged from [the assurance case](assurance-case.md), and re-affirmed by
this review rather than newly discovered:

- A compromise of the `edtf-postgres` publishing repository would produce a
  correctly-attested malicious extension that both of our gates accept.
  F-1 makes this marginally worse than documented, which is why it is being
  fixed.
- A window on OS-layer CVEs, whose length differs by layer — see F-2.
- Three OpenSSF Best Practices criteria and three Scorecard checks are
  structurally unreachable for a single maintainer. These are head-count
  facts; the mitigation is
  [GOVERNANCE.md](../GOVERNANCE.md#access-continuity), not a pretence that
  a second reviewer exists.

## Next review

Due by **2031-08-09** at the latest to keep the five-year window in the
OpenSSF Best Practices `security_review` criterion open, but expected far
sooner — a PostgreSQL major bump or any change to the publish pipeline's
ordering should trigger one regardless of the calendar.
