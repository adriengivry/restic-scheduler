#!/usr/bin/env bash
set -euo pipefail

required_vars=(
  RESTIC_REPOSITORY
  RESTIC_PASSWORD
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing required environment variable: ${var_name}" >&2
    exit 1
  fi
done

: "${BACKUP_CRON:=0 3 * * *}"
: "${CHECK_CRON:=0 6 * * *}"
: "${RESTIC_AUTO_INIT:=true}"

crontab_file="/etc/restic-scheduler.crontab"

initialize_repository() {
  if restic cat config >/dev/null 2>&1; then
    return
  fi

  if [[ "${RESTIC_AUTO_INIT}" != "true" ]]; then
    echo "Restic repository is not initialized and RESTIC_AUTO_INIT is disabled." >&2
    exit 1
  fi

  echo "Initializing restic repository"
  restic init
}

write_crontab() {
  : > "${crontab_file}"

  if [[ -n "${BACKUP_CRON}" ]]; then
    printf '%s /usr/local/bin/restic-job backup\n' "${BACKUP_CRON}" >> "${crontab_file}"
  fi

  if [[ -n "${CHECK_CRON}" ]]; then
    printf '%s /usr/local/bin/restic-job check\n' "${CHECK_CRON}" >> "${crontab_file}"
  fi

  if [[ ! -s "${crontab_file}" ]]; then
    echo "No jobs configured. Set BACKUP_CRON and/or CHECK_CRON." >&2
    exit 1
  fi
}

initialize_repository
restic unlock
write_crontab

echo "Configured cron jobs:"
cat "${crontab_file}"

exec /usr/local/bin/supercronic "${crontab_file}"
