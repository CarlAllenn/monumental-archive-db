# Roadmap

What this project intends to do — and deliberately not do — over roughly
the next year (written 2026-08-09). A roadmap is a statement of direction,
not a promise; when it changes, this file changes with it.

This repository is closer to "finished" than most. It publishes one image
with a deliberately fixed surface, so the honest roadmap is mostly about
*maintaining a guarantee*, not about growing features.

## Will do

- **Keep the remediation clock running.** The weekly cache-free rebuild is
  the product's central safety property: it caps exposure on the
  unpinnable OS layer at seven days
  ([0001](decisions/0001-own-the-installation.md)). Work that defends it —
  keeping the scheduled workflow green, keeping egress allowlists derived
  rather than guessed, keeping the trivy gate on pull requests and off the
  publish path — takes priority over anything additive.
- **Track the postgres major.** PostgreSQL 19 is the next real change to
  this image. The bump is gated on all three extensions being available for
  it from PGDG and on `edtf_postgres` publishing a `-pg19` image; it will
  land as a deliberate change with the decision recorded, not as a Renovate
  automerge.
- **Shrink the edtf build stage** once
  [CarlAllenn/edtf#144](https://github.com/CarlAllenn/edtf/issues/144)
  lands a minimal artifact image ([#5](https://github.com/CarlAllenn/monumental-archive-db/issues/5)).
  The current build stage is postgres-plus-extension when all we copy out
  is a handful of `edtf_postgres*` files.
- **Finish the supply-chain scoring work**
  ([#2](https://github.com/CarlAllenn/monumental-archive-db/issues/2)):
  OpenSSF Scorecard published, Best Practices at silver, REUSE compliance.
  Structurally unreachable checks are documented as such rather than
  chased.
- **Keep the docs honest about digests.** Every document here that names a
  digest or a version is a thing that can rot without failing anything.

## Will not do

Exclusions are use-case-gated rather than absolute — that keeps the
contribution door open without inviting scope creep.

- **No fourth extension speculatively.** The image is postgres plus
  PostGIS, pgaudit and `edtf_postgres` because the consuming archive needs
  exactly those three. A fourth stays out until a specific consumer needs
  it; a contribution backed by one is welcome, held to the same bar as the
  existing three — installed from a distribution we can refresh, pinned
  under the Renovate convention, and asserted in the smoke test.
- **No version tags, no releases.** This image has no version surface of
  its own; its "version" is the postgres major plus three extension pins.
  Consumers pin digests and Renovate resolves against `:main`. Inventing
  releases so that a scoring check has something to read would be
  ceremony that makes the artifact worse.
- **No application code, no migrations, no seed data.**
  `/docker-entrypoint-initdb.d` stays empty: the consuming archive is
  migration-defined, and an image that initialises schema is an image that
  fights its consumer's migration tool.
- **No QEMU builds, ever.** Emulated builds test the image on the wrong
  machine. If a new architecture cannot get a native runner, it does not
  ship.
- **No inheriting a prebuilt extension image as our base.** This is the
  standing decision in [0001](decisions/0001-own-the-installation.md), and
  it is the one exclusion that will look like a free simplification to
  every future reader: it would inherit an apt layer we cannot refresh, and
  the weekly rebuild would stop meaning anything.
- **No SBOM-scanning job or dependency-snapshot submission.** SBOMs are
  attached to what we publish; trivy already opens the actual artifact and
  matches against the same databases, so a snapshot pipeline is a second
  notification surface for a gap that is not open.
