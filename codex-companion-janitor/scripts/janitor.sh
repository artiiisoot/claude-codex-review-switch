#!/bin/sh
# Codex Companion janitor: collect companion chats into a section, then purge them.
#
#   janitor.sh collect   move "Codex Companion Task:" chats into the section
#   janitor.sh purge     delete the chats sitting in that section
#   janitor.sh run       collect before :05, purge after (what launchd calls)
#   janitor.sh install   write the launchd job (18:00 + 18:10 daily)
#   janitor.sh uninstall remove the launchd job
#   janitor.sh status    section id, pending counts, job state
#
# Env: CODEX_HOME (default ~/.codex), SECTION_NAME (default "Codex Companion"),
#      TITLE_PREFIX (default "Codex Companion Task:"), TRASH_DAYS (default 7),
#      DRY_RUN=1 to print what purge would do and change nothing.
set -eu

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
SECTION_NAME="${SECTION_NAME:-Codex Companion}"
TITLE_PREFIX="${TITLE_PREFIX:-Codex Companion Task:}"
TRASH_DAYS="${TRASH_DAYS:-7}"
LABEL="com.artiiisoot.codex-companion-janitor"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

STATE_DB=""
HIST_DB=""
INDEX="$CODEX_HOME/session_index.jsonl"
TRASH="$CODEX_HOME/.janitor-trash"

die() { echo "janitor: $1" >&2; exit 1; }
sq() { printf '%s' "$1" | sed "s/'/''/g"; }   # single-quote escape for SQL

find_dbs() {
  [ -d "$CODEX_HOME" ] || die "no CODEX_HOME at $CODEX_HOME"
  # state_N.sqlite / thread_history_N.sqlite: take the highest N present.
  STATE_DB=$(ls "$CODEX_HOME"/state_*.sqlite 2>/dev/null | sort -V | tail -1 || true)
  HIST_DB=$(ls "$CODEX_HOME"/thread_history_*.sqlite 2>/dev/null | sort -V | tail -1 || true)
  [ -n "$STATE_DB" ] || die "no state_*.sqlite in $CODEX_HOME"
  command -v sqlite3 >/dev/null || die "sqlite3 not found"
}

section_id() {
  sqlite3 "$STATE_DB" \
    "SELECT id FROM thread_sections WHERE name = '$(sq "$SECTION_NAME")' LIMIT 1;"
}

cmd_collect() {
  find_dbs
  sid=$(section_id)
  # The section is the user's; never recreate it silently.
  [ -n "$sid" ] || die "section \"$SECTION_NAME\" not found in Codex - create it in the app first"
  before=$(sqlite3 "$STATE_DB" "SELECT count(*) FROM threads
      WHERE title LIKE '$(sq "$TITLE_PREFIX")%' AND archived = 0
        AND is_pinned = 0 AND thread_section_id IS NULL;")
  if [ "$before" -eq 0 ]; then echo "collect: nothing to move"; return 0; fi
  sqlite3 "$STATE_DB" "UPDATE threads
      SET thread_section_id = '$(sq "$sid")',
          section_entered_at_ms = CAST(strftime('%s','now') AS INTEGER) * 1000
      WHERE title LIKE '$(sq "$TITLE_PREFIX")%' AND archived = 0
        AND is_pinned = 0 AND thread_section_id IS NULL;"
  echo "collect: moved $before chat(s) into \"$SECTION_NAME\""
}

cmd_purge() {
  find_dbs
  sid=$(section_id)
  [ -n "$sid" ] || die "section \"$SECTION_NAME\" not found in Codex"
  where="thread_section_id = '$(sq "$sid")' AND title LIKE '$(sq "$TITLE_PREFIX")%' AND is_pinned = 0"

  ids=$(sqlite3 "$STATE_DB" "SELECT id FROM threads WHERE $where;")
  [ -n "$ids" ] || { echo "purge: nothing to delete"; return 0; }
  n=$(printf '%s\n' "$ids" | wc -l | tr -d ' ')

  if [ "${DRY_RUN:-}" = 1 ]; then
    echo "purge (dry run): would delete $n chat(s):"
    sqlite3 "$STATE_DB" "SELECT id || '  ' || title FROM threads WHERE $where;"
    return 0
  fi

  stamp=$(date +%Y-%m-%d_%H%M%S)
  bin="$TRASH/$stamp"
  mkdir -p "$bin"
  # Rollouts and DB copies go to the trash bin, not straight to rm, so a bad
  # match is recoverable for TRASH_DAYS.
  cp "$STATE_DB" "$bin/$(basename "$STATE_DB").bak"
  if [ -n "$HIST_DB" ]; then cp "$HIST_DB" "$bin/$(basename "$HIST_DB").bak"; fi

  sqlite3 "$STATE_DB" "SELECT rollout_path FROM threads WHERE $where;" | while read -r p; do
    [ -n "$p" ] && [ -f "$p" ] && mv "$p" "$bin/" || true
  done

  printf '%s\n' "$ids" > "$bin/ids.txt"
  list=$(printf "'%s'," $ids | sed 's/,$//')

  sqlite3 "$STATE_DB" "
    DELETE FROM thread_attachments WHERE thread_id IN ($list);
    DELETE FROM thread_read_receipts WHERE thread_id IN ($list);
    DELETE FROM thread_spawn_edges WHERE child_thread_id IN ($list) OR parent_thread_id IN ($list);
    DELETE FROM threads WHERE id IN ($list);"
  if [ -n "$HIST_DB" ]; then sqlite3 "$HIST_DB" "
    DELETE FROM thread_items WHERE thread_id IN ($list);
    DELETE FROM thread_turns WHERE thread_id IN ($list);
    DELETE FROM thread_realtime_items WHERE thread_id IN ($list);"; fi

  if [ -f "$INDEX" ]; then
    cp "$INDEX" "$bin/$(basename "$INDEX").bak"
    grep -v -F -f "$bin/ids.txt" "$INDEX" > "$INDEX.tmp" || true
    mv "$INDEX.tmp" "$INDEX"
  fi

  find "$TRASH" -mindepth 1 -maxdepth 1 -type d -mtime "+$TRASH_DAYS" -exec rm -rf {} + 2>/dev/null || true
  echo "purge: deleted $n chat(s); recoverable in $bin for $TRASH_DAYS day(s)"
}

cmd_run() {
  # One launchd job for both times: before :05 is the 18:00 firing, after is 18:10.
  if [ "$(date +%M)" -lt 5 ]; then cmd_collect; else cmd_purge; fi
}

cmd_install() {
  mkdir -p "$(dirname "$PLIST")"
  cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/sh</string><string>$SELF</string><string>run</string></array>
  <key>StartCalendarInterval</key>
  <array>
    <dict><key>Hour</key><integer>18</integer><key>Minute</key><integer>0</integer></dict>
    <dict><key>Hour</key><integer>18</integer><key>Minute</key><integer>10</integer></dict>
  </array>
  <key>StandardOutPath</key><string>$CODEX_HOME/.janitor.log</string>
  <key>StandardErrorPath</key><string>$CODEX_HOME/.janitor.log</string>
</dict></plist>
PLISTEOF
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST"
  echo "installed: $LABEL (18:00 collect, 18:10 purge) -> $PLIST"
}

cmd_uninstall() {
  launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "uninstalled: $LABEL"
}

cmd_status() {
  find_dbs
  sid=$(section_id)
  echo "CODEX_HOME : $CODEX_HOME"
  echo "state db   : $STATE_DB"
  echo "section    : ${sid:-(missing)} \"$SECTION_NAME\""
  if [ -n "$sid" ]; then
    echo "to collect : $(sqlite3 "$STATE_DB" "SELECT count(*) FROM threads WHERE title LIKE '$(sq "$TITLE_PREFIX")%' AND archived=0 AND is_pinned=0 AND thread_section_id IS NULL;")"
    echo "to purge   : $(sqlite3 "$STATE_DB" "SELECT count(*) FROM threads WHERE thread_section_id='$(sq "$sid")' AND title LIKE '$(sq "$TITLE_PREFIX")%' AND is_pinned=0;")"
  fi
  if [ -f "$PLIST" ]; then launchctl list | grep -q "$LABEL" && echo "schedule   : loaded" || echo "schedule   : plist present, not loaded"
  else echo "schedule   : not installed"; fi
}

case "${1:-status}" in
  collect) cmd_collect ;;
  purge) cmd_purge ;;
  run) cmd_run ;;
  install) cmd_install ;;
  uninstall) cmd_uninstall ;;
  status) cmd_status ;;
  *) die "unknown command: $1" ;;
esac
