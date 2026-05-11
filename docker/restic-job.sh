#!/usr/bin/env bash
set -euo pipefail

job="${1:-}"
[[ -n "$job" ]] || { echo "Usage: restic-job <backup|check>" >&2; exit 1; }

: "${BACKUP_PATH:=/data}"
: "${CHECK_ARGS:=--read-data-subset=10%}"
: "${RESTIC_BACKUP_ARGS:=--verbose --one-file-system}"
: "${RESTIC_FORGET_ARGS:=--keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune}"
: "${RESTIC_RETRY_LOCK:=35m}"
: "${JOB_LOCK_FILE:=/var/run/restic-scheduler.lock}"

timestamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }
on_exit() {
  local code=$?
  [[ $code -eq 0 ]] || echo "### FAILED $job $(timestamp) ###" >&2
  exit $code
}
trap on_exit EXIT

exec 9>"$JOB_LOCK_FILE"
if ! flock -n 9; then
  echo "Another restic job is already running, skipping $job." >&2
  exit 0
fi

restic unlock

case "$job" in
  backup)
    echo "### BEGIN BACKUP $(timestamp) ###"
    read -ra backup_args <<< "${RESTIC_BACKUP_ARGS:-}"
    restic --retry-lock "$RESTIC_RETRY_LOCK" backup "$BACKUP_PATH" "${backup_args[@]}"
    read -ra forget_args <<< "${RESTIC_FORGET_ARGS:-}"
    [[ ${#forget_args[@]} -gt 0 ]] && restic --retry-lock "$RESTIC_RETRY_LOCK" forget "${forget_args[@]}"
    [[ -n "${PING_URL_BACKUP:-}" ]] && curl -fsS --retry 3 --max-time 30 "$PING_URL_BACKUP" >/dev/null
    echo "### END BACKUP $(timestamp) ###"
    ;;
  check)
    echo "### BEGIN CHECK $(timestamp) ###"
    read -ra check_args <<< "${CHECK_ARGS:-}"
    restic --retry-lock "$RESTIC_RETRY_LOCK" check "${check_args[@]}"
    [[ -n "${PING_URL_CHECK:-}" ]] && curl -fsS --retry 3 --max-time 30 "$PING_URL_CHECK" >/dev/null
    echo "### END CHECK $(timestamp) ###"
    ;;
  *)
    echo "Unknown job: $job" >&2
    exit 1
    ;;
esac
