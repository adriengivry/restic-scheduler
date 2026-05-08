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

repository_ready() {
  restic cat config >/dev/null 2>&1
}

wait_for_repository_ready() {
  local attempts="${1:-5}"
  local delay_seconds="${2:-2}"

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if repository_ready; then
      return 0
    fi

    if (( attempt < attempts )); then
      sleep "${delay_seconds}"
    fi
  done

  return 1
}

unlock_repository() {
  local unlock_output

  if unlock_output="$(restic unlock 2>&1)"; then
    if [[ -n "${unlock_output}" ]]; then
      printf '%s\n' "${unlock_output}"
    fi
    return
  fi

  if [[ "${unlock_output}" == *"config file does not exist"* ]] \
    || [[ "${unlock_output}" == *"unable to open config file"* ]] \
    || [[ "${unlock_output}" == *"Is there a repository at the following location?"* ]]; then
    return
  fi

  printf '%s\n' "${unlock_output}" >&2
  exit 1
}

initialize_repository() {
  if wait_for_repository_ready 3 2; then
    return
  fi

  if [[ "${RESTIC_AUTO_INIT}" != "true" ]]; then
    echo "Restic repository is not initialized and RESTIC_AUTO_INIT is disabled." >&2
    exit 1
  fi

  echo "Initializing restic repository"
  local init_output
  if init_output="$(restic init 2>&1)"; then
    printf '%s\n' "${init_output}"
    return
  fi

  if [[ "${init_output}" == *"already initialized"* ]] && wait_for_repository_ready 10 2; then
    echo "Restic repository was initialized concurrently; continuing"
    return
  fi

  printf '%s\n' "${init_output}" >&2
  exit 1
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

unlock_repository
initialize_repository
unlock_repository
write_crontab

echo "Configured cron jobs:"
cat "${crontab_file}"

exec /usr/local/bin/supercronic "${crontab_file}"
