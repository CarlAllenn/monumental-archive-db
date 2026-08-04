# The Monumental Archive's database image: official Postgres plus audited
# extensions (PostGIS, pgaudit, edtf_postgres). Renovate manages the FROM
# digest. Base is Debian 13 (trixie).
#
# Why the official postgres image rather than postgis/postgis: PostGIS is
# installed HERE, at our build time, so its dependencies resolve fresh from
# trixie-security on every uncached build. postgis/postgis bakes them in at
# ITS build time — which once froze libexpat1 and libnss3 at versions
# carrying 22 CVEs no rebuild of ours could ever refresh, because the
# packages were not ours to refresh. A package you did not install is a
# package you cannot refresh (docs/decisions/0001-own-the-installation.md).
# The official image is also genuinely multi-arch; postgis/postgis
# publishes amd64 only.

# renovate: datasource=github-releases depName=CarlAllenn/edtf
ARG EDTF_POSTGRES_VERSION=1.1.2
# Checksums are pinned per architecture and verified by BuildKit before the
# bytes are used (fail-closed: a wrong hash aborts the build with "digest
# mismatch"). Deliberately NOT Renovate-tracked:
# scripts/check-edtf-attestation.sh proves — in CI, against the release's
# GitHub attestation — that these are the values edtf's own publish
# workflow produced. A pinned hash alone would only prove the download did
# not change; the attestation is what proves it authentic.
ARG EDTF_SHA256_AMD64=837281408b9b2e75fe0cb5fe933183db3355ba2f733af029c9a4aca017ee3ad9
ARG EDTF_SHA256_ARM64=a9870a844b591fa66a76f04b97bcf3ff51abe0c83e136a4bdf56af453b7e9389

FROM postgres:18-trixie@sha256:3a82e1f56c8f0f5616a11103ac3d47e632c3938698946a7ad26da0df1334744a AS base

# --- edtf-postgres: prebuilt, attested, checksum-verified ------------------
# EDTF validation as a native extension: the same edtf-core the archive's
# web app runs via WASM, so the two layers can never diverge. Consumed as a
# published artifact from CarlAllenn/edtf rather than compiled here — the
# image compiles nothing, which is what makes a native arm64 build cheap.
#
# Both architectures are fetched and both checksums verified on every build,
# whichever architecture is being built: the tarballs are ~3MB, this stage is
# discarded, and it means a wrong checksum is caught even for the platform
# this particular build is not producing. The extracted tree is exactly the
# runtime paths, so the runtime stage copies it whole.
FROM base AS edtf
ARG TARGETARCH
ARG EDTF_POSTGRES_VERSION
ARG EDTF_SHA256_AMD64
ARG EDTF_SHA256_ARM64
ADD --checksum=sha256:${EDTF_SHA256_AMD64} \
  https://github.com/CarlAllenn/edtf/releases/download/edtf-postgres-v${EDTF_POSTGRES_VERSION}/edtf_postgres-${EDTF_POSTGRES_VERSION}-pg18-linux-amd64.tar.gz \
  /tmp/edtf-amd64.tar.gz
ADD --checksum=sha256:${EDTF_SHA256_ARM64} \
  https://github.com/CarlAllenn/edtf/releases/download/edtf-postgres-v${EDTF_POSTGRES_VERSION}/edtf_postgres-${EDTF_POSTGRES_VERSION}-pg18-linux-arm64.tar.gz \
  /tmp/edtf-arm64.tar.gz
RUN mkdir -p /pkgroot \
  && tar xzf "/tmp/edtf-${TARGETARCH}.tar.gz" -C /pkgroot

# --- runtime ---------------------------------------------------------------
FROM base

# PostGIS and pgaudit from PGDG (the repo ships in the base image). PostGIS
# drags in the GDAL stack, and with it libexpat1 and libnss3 — absent from
# the base, installed here, resolved from trixie-security at build time.
#
# ARG, not a bare version in the apt line: Renovate's regex manager matches
# `# renovate:` comments above `ARG *_VERSION=` and nothing else, so a pin
# written inline would be tracked by nothing. PostGIS is the most important
# package in the image; its version must never lose Renovate coverage.
# renovate: datasource=deb depName=postgresql-18-postgis-3
ARG POSTGIS_VERSION=3.6.4+dfsg-2.pgdg13+1
# renovate: datasource=deb depName=postgresql-18-pgaudit
ARG PGAUDIT_VERSION=18.0-3.pgdg13+1
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    "postgresql-18-postgis-3=${POSTGIS_VERSION}" \
    "postgresql-18-pgaudit=${PGAUDIT_VERSION}" \
  && rm -rf /var/lib/apt/lists/*

COPY --from=edtf /pkgroot/ /

# gosu exists to drop root→postgres; this image starts as postgres (USER
# below), so it's dead code — and it ships with stale-Go-stdlib CVEs. Gone.
# The initdb.d directory is emptied because the consuming archive is
# migration-defined: extensions are created by its schema tooling, never by
# container init.
RUN rm -f /docker-entrypoint-initdb.d/* /usr/local/bin/gosu

# Preloads baked into the image so every consumer (compose stacks, schema
# tooling's throwaway dev containers, production) behaves identically:
# pgaudit and pg_stat_statements require shared preload.
# wal_level=logical: the archive's live read path is logical replication
# (ElectricSQL); baked here so every consumer matches production exactly.
CMD ["postgres", \
  "-c", "shared_preload_libraries=pg_stat_statements,pgaudit", \
  "-c", "wal_level=logical"]

# Non-root by default; the official entrypoint supports starting as the
# postgres user directly (it skips its root-phase chown dance).
USER postgres

HEALTHCHECK --interval=5s --timeout=3s --retries=10 \
  CMD ["pg_isready", "-U", "postgres"]
