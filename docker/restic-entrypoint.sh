#!/usr/bin/env bash
set -euo pipefail

for var in RESTIC_REPOSITORY RESTIC_PASSWORD; do
  [[ -n "${!var:-}" ]] || { echo "Missing required environment variable: ${var}" >&2; exit 1; }
done

: "${BACKUP_CRON:=0 3 * * *}"
: "${CHECK_CRON:=0 6 * * *}"
: "${RESTIC_AUTO_INIT:=true}"

crontab_file="/etc/restic-scheduler.crontab"

repository_ready() {
  restic cat config --no-lock >/dev/null 2>&1
}

unlock_repository() {
  local out
  if out="$(restic unlock 2>&1)"; then
    [[ -z "$out" ]] || echo "$out"
    return
  fi
  case "$out" in
    *"config file does not exist"*|*"unable to open config file"*|*"Is there a repository at the following location?"*)
      return ;;
  esac
  echo "$out" >&2
  exit 1
}

ensure_repository_exists() {
  for ((i = 1; i <= 5; i++)); do
    repository_ready && return
    (( i < 5 )) && sleep 2
  done

  if [[ "${RESTIC_AUTO_INIT}" != "true" ]]; then
    echo "Restic repository is not accessible and RESTIC_AUTO_INIT is disabled." >&2
    exit 1
  fi

  echo "Initializing restic repository"
  local out
  if out="$(restic init 2>&1)"; then
    echo "$out"
  elif [[ "$out" != *"already initialized"* ]]; then
    echo "$out" >&2
    exit 1
  fi

  for ((i = 1; i <= 10; i++)); do
    repository_ready && return
    sleep 2
  done

  echo "Restic repository is not ready after initialization." >&2
  exit 1
}

unlock_repository
ensure_repository_exists

: > "$crontab_file"
[[ -n "${BACKUP_CRON}" ]] && printf '%s /usr/local/bin/restic-job backup\n' "${BACKUP_CRON}" >> "$crontab_file"
[[ -n "${CHECK_CRON}" ]] && printf '%s /usr/local/bin/restic-job check\n' "${CHECK_CRON}" >> "$crontab_file"

[[ -s "$crontab_file" ]] || { echo "No jobs configured. Set BACKUP_CRON and/or CHECK_CRON." >&2; exit 1; }

echo "Configured cron jobs:"
cat "$crontab_file"

exec supercronic "$crontab_file"
