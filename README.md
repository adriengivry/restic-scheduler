# restic-scheduler

Reusable container image for scheduled `restic` backups and `restic check` runs, intended to be dropped into any stack with only environment variables and a mounted backup path.

## What it does

- initializes the repository automatically by default
- clears stale restic locks at startup and before each job
- runs scheduled backup and check jobs with `supercronic`
- prevents overlapping jobs with a local lock file
- optionally calls healthcheck/ping URLs after successful jobs

## Required environment variables

| Variable | Description |
| --- | --- |
| `RESTIC_REPOSITORY` | Restic repository URL, including your S3 endpoint/bucket path. |
| `RESTIC_PASSWORD` | Repository password. |

S3-compatible backends typically also need credentials such as `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.

## Optional environment variables

| Variable | Default |
| --- | --- |
| `BACKUP_CRON` | `0 3 * * *` |
| `CHECK_CRON` | `0 6 * * *` |
| `BACKUP_PATH` | `/data` |
| `CHECK_ARGS` | `--read-data-subset=10%` |
| `RESTIC_BACKUP_ARGS` | `--verbose --one-file-system` |
| `RESTIC_FORGET_ARGS` | `--keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune` |
| `RESTIC_AUTO_INIT` | `true` |
| `PING_URL_BACKUP` | unset |
| `PING_URL_CHECK` | unset |
| `JOB_LOCK_FILE` | `/var/run/restic-scheduler.lock` |

Set `BACKUP_CRON` or `CHECK_CRON` to an empty value to disable that job.

## Example

```yaml
services:
  restic:
    image: ghcr.io/adriengivry/restic-scheduler:latest
    restart: unless-stopped
    environment:
      AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}
      AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY}
      RESTIC_REPOSITORY: s3:https://s3.example.com/my-bucket/restic
      RESTIC_PASSWORD: ${RESTIC_PASSWORD}
      BACKUP_CRON: "0 3 * * *"
      CHECK_CRON: "0 6 * * *"
      BACKUP_PATH: /data
    volumes:
      - my-data:/data:ro
      - restic-cache:/root/.cache/restic
```

## Local test stack

A simple local test setup lives under `test/` and uses a local restic repository volume.

## Make targets

```sh
make
make test
```

| Target | Description |
| --- | --- |
| `make` / `make build` | Builds the local image as `restic-scheduler:local`. |
| `make test` | Builds the test image, starts the local test stack, runs backup and check jobs, verifies a snapshot exists, and cleans everything up. |

`make test` requires `docker compose` or `docker-compose`.

