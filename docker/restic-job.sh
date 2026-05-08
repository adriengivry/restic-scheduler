#!/usr/bin/env bash
set -euo pipefail

job_name="${1:-}"

if [[ -z "${job_name}" ]]; then
  echo "Usage: restic-job <backup|check>" >&2
  exit 1
fi

: "${BACKUP_PATH:=/data}"
: "${CHECK_ARGS:=--read-data-subset=10%}"
: "${RESTIC_BACKUP_ARGS:=--verbose --one-file-system}"
: "${RESTIC_FORGET_ARGS:=--keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune}"
: "${JOB_LOCK_FILE:=/var/run/restic-scheduler.lock}"

timestamp() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

read_args() {
  local raw_value="${1:-}"
  local -n target_ref="$2"

  target_ref=()
  if [[ -n "${raw_value}" ]]; then
    read -r -a target_ref <<<"${raw_value}"
  fi
}

ping_on_success() {
  local url="${1:-}"

  if [[ -n "${url}" ]]; then
    curl -fsS --retry 3 --max-time 30 "${url}" >/dev/null
  fi
}

exec 9>"${JOB_LOCK_FILE}"
if ! flock -n 9; then
  echo "Another restic job is already running, skipping ${job_name}." >&2
  exit 0
fi

restic unlock

case "${job_name}" in
  backup)
    echo "### BEGIN BACKUP $(timestamp) ###"
    read_args "${RESTIC_BACKUP_ARGS}" backup_args
    restic backup "${BACKUP_PATH}" "${backup_args[@]}"

    read_args "${RESTIC_FORGET_ARGS}" forget_args
    if [[ "${#forget_args[@]}" -gt 0 ]]; then
      restic forget "${forget_args[@]}"
    fi

    ping_on_success "${PING_URL_BACKUP:-}"
    echo "### END BACKUP $(timestamp) ###"
    ;;
  check)
    echo "### BEGIN CHECK $(timestamp) ###"
    read_args "${CHECK_ARGS}" check_args
    restic check "${check_args[@]}"
    ping_on_success "${PING_URL_CHECK:-}"
    echo "### END CHECK $(timestamp) ###"
    ;;
  *)
    echo "Unknown job: ${job_name}" >&2
    exit 1
    ;;
esac
