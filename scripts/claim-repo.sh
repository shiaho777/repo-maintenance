#!/bin/sh
# Shared claims for concurrent repo-maintenance processes.
# Every local coding-agent harness uses ~/.agents/repo-maintenance, so two sessions
# cannot vet or ship the same repo whether they are Grok, Claude Code, Codex, Cursor, or another CLI.
# The holder is the nearest long-lived parent of this command, so the lock outlives one shell
# command and dies with that process. No harness name list: a future CLI works the same way.
# Chats that share a process are split by the session id the harness exports.
# A dead holder is stolen. Seen entries stay until deleted by hand.
set -eu

init_roots() {
  if [ -n "${REPO_CLAIM_ROOT:-}" ]; then
    ROOT=$REPO_CLAIM_ROOT
    LEGACY=
    return
  fi
  ROOT=$HOME/.agents/repo-maintenance
  LEGACY=$HOME/.grok/repo-maintenance
  if [ -d "$LEGACY" ] && [ ! -e "$ROOT" ]; then
    mkdir -p "$HOME/.agents"
    mv "$LEGACY" "$ROOT"
    LEGACY=
  fi
  if [ -z "${LEGACY:-}" ] || [ ! -d "$LEGACY" ] || [ "$LEGACY" = "$ROOT" ]; then
    LEGACY=
  fi
}

init_roots
ACTIVE="$ROOT/active"
SEEN="$ROOT/seen"
mkdir -p "$ACTIVE" "$SEEN"

usage() {
  echo "usage: claim-repo.sh claim|release|seen OWNER/REPO" >&2
  echo "       claim-repo.sh list-active|whoami" >&2
  exit 2
}

base_name() {
  b=${1##*/}
  printf '%s' "$b" | tr '[:upper:]' '[:lower:]'
}

# Shells and one-shot wrappers sit between this script and the session process.
is_skippable() {
  case "$1" in
    sh|bash|zsh|dash|fish|nu|ksh|tcsh|csh|env|nice|nohup|timeout|gtimeout|stdbuf|xargs|time)
      return 0
      ;;
  esac
  return 1
}

holder_pid() {
  if [ -n "${REPO_CLAIM_PID:-}" ]; then
    printf '%s\n' "$REPO_CLAIM_PID"
    return
  fi
  pid=$PPID
  while [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null | awk 'NR==1 { print $1 }')
    if ! is_skippable "$(base_name "$comm")"; then
      printf '%s\n' "$pid"
      return
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  done
  echo "claim-repo: no long-lived parent; refusing to lock as a short-lived shell" >&2
  exit 2
}

# Stable for the whole chat, and different across chats that share one process.
# Per-turn ids are intentionally absent. When a harness exports none, the
# process id plus its start time is the session.
session_id() {
  if [ -n "${REPO_CLAIM_SESSION:-}" ]; then
    printf '%s\n' "$REPO_CLAIM_SESSION"
    return
  fi
  key=
  for key in \
    GROK_SESSION_ID \
    CLAUDE_CODE_SESSION_ID \
    CLAUDE_CODE_REMOTE_SESSION_ID \
    CODEX_THREAD_ID \
    CODEX_SESSION_ID
  do
    eval "val=\${$key:-}"
    if [ -n "$val" ]; then
      printf '%s\n' "$val" | tr -d '\n'
      printf '\n'
      return
    fi
  done
  pid=$(holder_pid)
  printf '%s:%s\n' "$pid" "$(lstart_of "$pid")"
}

lstart_of() {
  ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//;s/ *$//'
}

slug_of() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk 'NR==1 { print $1 }'
  else
    printf '%s' "$1" | sha256sum | awk 'NR==1 { print $1 }'
  fi
}

require_repo() {
  case "${1:-}" in
    */*)
      owner=${1%%/*}
      name=${1#*/}
      case "$owner" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
      case "$name" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
      [ "$owner/$name" = "$1" ] || return 1
      return 0
      ;;
    *) return 1 ;;
  esac
}

meta_get() {
  # meta_get FILE KEY
  awk -F= -v k="$2" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' "$1" 2>/dev/null || true
}

holder_alive() {
  # holder_alive METAFILE
  pid=$(meta_get "$1" pid)
  saved=$(meta_get "$1" lstart)
  [ -n "$pid" ] && [ -n "$saved" ] || return 1
  current=$(lstart_of "$pid")
  [ -n "$current" ] && [ "$current" = "$saved" ]
}

write_meta() {
  # write_meta DIR REPO
  pid=$(holder_pid)
  started=$(lstart_of "$pid")
  if [ -z "$started" ]; then
    echo "claim-repo: holder $pid is not running" >&2
    exit 2
  fi
  tmp="$1/meta.$$"
  printf 'pid=%s\nlstart=%s\nsession=%s\nrepo=%s\n' "$pid" "$started" "$(session_id)" "$2" > "$tmp"
  mv -f "$tmp" "$1/meta"
}

we_hold() {
  # Same live parent and the same chat. A lock with no session line is an older claim.
  [ -f "$1/meta" ] || return 1
  holder_alive "$1/meta" || return 1
  pid=$(meta_get "$1/meta" pid)
  [ "$pid" = "$(holder_pid)" ] || return 1
  saved=$(meta_get "$1/meta" session)
  if [ -z "$saved" ]; then
    return 0
  fi
  [ "$saved" = "$(session_id)" ]
}

lock_dir() {
  printf '%s/active/%s\n' "$1" "$(slug_of "$2")"
}

claim_active() {
  repo=$1
  if [ -n "$LEGACY" ]; then
    ldir=$(lock_dir "$LEGACY" "$repo")
    if [ -d "$ldir" ] && [ -f "$ldir/meta" ] && holder_alive "$ldir/meta"; then
      if we_hold "$ldir"; then
        echo owned
        exit 0
      fi
      held=$(meta_get "$ldir/meta" pid)
      echo "busy $repo held by $held" >&2
      exit 1
    fi
  fi
  dir="$ACTIVE/$(slug_of "$repo")"
  tries=0
  while [ "$tries" -lt 5 ]; do
    tries=$((tries + 1))
    if mkdir "$dir" 2>/dev/null; then
      write_meta "$dir" "$repo"
      echo acquired
      exit 0
    fi
    if we_hold "$dir"; then
      echo owned
      exit 0
    fi
    if [ -f "$dir/meta" ] && holder_alive "$dir/meta"; then
      held=$(meta_get "$dir/meta" pid)
      echo "busy $repo held by $held" >&2
      exit 1
    fi
    # Missing meta is an in-progress claim unless the directory is old.
    if [ ! -f "$dir/meta" ]; then
      now=$(date +%s)
      born=$(stat -f %m "$dir" 2>/dev/null || stat -c %Y "$dir" 2>/dev/null || echo "$now")
      if [ $((now - born)) -lt 15 ]; then
        sleep 0.2
        continue
      fi
    fi
    if mv "$dir" "$dir.stale.$$" 2>/dev/null; then
      rm -rf "$dir.stale.$$"
    fi
  done
  echo "busy $repo" >&2
  exit 1
}

release_active() {
  repo=$1
  held=
  foreign=0
  for root in $ROOT ${LEGACY:-}; do
    [ -n "$root" ] || continue
    dir=$(lock_dir "$root" "$repo")
    [ -d "$dir" ] || continue
    if we_hold "$dir"; then
      held="$held $dir"
    elif [ -f "$dir/meta" ] && holder_alive "$dir/meta"; then
      foreign=1
    fi
  done
  if [ "$foreign" = 1 ]; then
    echo "not our claim $repo" >&2
    exit 1
  fi
  for dir in $held; do
    mv "$dir" "$dir.releasing.$$" && rm -rf "$dir.releasing.$$"
  done
  exit 0
}

mark_seen() {
  repo=$1
  slug=$(slug_of "$repo")
  if [ -n "$LEGACY" ] && [ -d "$LEGACY/seen/$slug" ]; then
    exit 1
  fi
  dir="$SEEN/$slug"
  if mkdir "$dir" 2>/dev/null; then
    printf '%s\n' "$repo" > "$dir/name"
    exit 0
  fi
  exit 1
}

list_one_root() {
  [ -d "$1" ] || return 0
  find "$1" -mindepth 1 -maxdepth 1 -type d ! -name '*.stale.*' ! -name '*.releasing.*' 2>/dev/null |
    while IFS= read -r dir; do
      if [ -f "$dir/meta" ] && holder_alive "$dir/meta"; then
        meta_get "$dir/meta" repo
      fi
    done
}

list_active() {
  list_one_root "$ACTIVE"
  if [ -n "$LEGACY" ]; then
    list_one_root "$LEGACY/active"
  fi
}

whoami() {
  pid=$(holder_pid)
  comm=$(ps -o comm= -p "$pid" 2>/dev/null | awk 'NR==1 { print $1 }')
  printf '%s %s %s\n' "$pid" "$(base_name "$comm")" "$(session_id)"
}

cmd=${1:-}
case "$cmd" in
  claim|release|seen)
    repo=${2:-}
    require_repo "$repo" || usage
    case "$cmd" in
      claim) claim_active "$repo" ;;
      release) release_active "$repo" ;;
      seen) mark_seen "$repo" ;;
    esac
    ;;
  list-active)
    list_active
    ;;
  whoami)
    whoami
    ;;
  *)
    usage
    ;;
esac
