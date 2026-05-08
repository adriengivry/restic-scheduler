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
| `RESTIC_RETRY_LOCK` | `35m` |
| `RESTIC_AUTO_INIT` | `true` |
| `PING_URL_BACKUP` | unset |
| `PING_URL_CHECK` | unset |
| `JOB_LOCK_FILE` | `/var/run/restic-scheduler.lock` |

Set `BACKUP_CRON` or `CHECK_CRON` to an empty value to disable that job.

`RESTIC_RETRY_LOCK` controls how long backup/check/forget wait for an existing repository lock. If you want jobs to outwait stale locks from crashed processes, this value should be longer than restic's stale-lock window, which is roughly 30 minutes by default.

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

## Make targets

```sh
make
make test
```

| Target | Description |
| --- | --- |
| `make` / `make build` | Builds the local image as `restic-scheduler:local`. |
| `make test` | Builds the image once, runs it with different settings, verifies scheduled backup and check runs, confirms restart against an existing repository works, confirms cron jobs run, confirms ping callbacks fire, prints phase logs, and cleans everything up. |

`make test` requires `docker compose` or `docker-compose`.

The test stack mounts `test/data`, uses a local restic repository volume, and includes a tiny local HTTP receiver so scheduled backup/check jobs can prove both cron execution and ping callback delivery without any external service.
