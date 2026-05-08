FROM alpine:3.22

ARG SUPERCRONIC_VERSION=v0.2.38

RUN set -eux; \
    apk add --no-cache bash ca-certificates curl restic tzdata util-linux; \
    arch="$(apk --print-arch)"; \
    case "${arch}" in \
      x86_64) supercronic_arch='amd64' ;; \
      aarch64) supercronic_arch='arm64' ;; \
      armv7) supercronic_arch='arm' ;; \
      *) echo "Unsupported architecture: ${arch}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/supercronic \
      "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-${supercronic_arch}"; \
    chmod +x /usr/local/bin/supercronic

COPY docker/restic-entrypoint.sh /usr/local/bin/restic-entrypoint
COPY docker/restic-job.sh /usr/local/bin/restic-job

RUN chmod +x /usr/local/bin/restic-entrypoint /usr/local/bin/restic-job

ENTRYPOINT ["/usr/local/bin/restic-entrypoint"]
