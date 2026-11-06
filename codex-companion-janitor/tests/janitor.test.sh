#!/bin/sh
# One runnable check: collect moves only matching chats, purge removes them
# and leaves pinned / unrelated / other-section chats alone.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
J="$HERE/../scripts/janitor.sh"
H=$(mktemp -d)
trap 'rm -rf "$H"' EXIT
export CODEX_HOME="$H"

mkdir -p "$H/sessions"
sqlite3 "$H/state_5.sqlite" "
CREATE TABLE thread_sections (id TEXT PRIMARY KEY, name TEXT NOT NULL, appearance TEXT);
CREATE TABLE threads (id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL, title TEXT NOT NULL,
  archived INTEGER NOT NULL DEFAULT 0, is_pinned INTEGER NOT NULL DEFAULT 0,
  thread_section_id TEXT, section_entered_at_ms INTEGER);
CREATE TABLE thread_attachments (id TEXT PRIMARY KEY, thread_id TEXT NOT NULL);
CREATE TABLE thread_read_receipts (thread_id TEXT PRIMARY KEY, revision TEXT NOT NULL DEFAULT '');
CREATE TABLE thread_spawn_edges (parent_thread_id TEXT, child_thread_id TEXT PRIMARY KEY, status TEXT);
INSERT INTO thread_sections VALUES ('sec-1','Codex Companion',NULL),('sec-2','Pinned',NULL);
INSERT INTO threads (id,rollout_path,title) VALUES
  ('t1','$H/sessions/t1.jsonl','Codex Companion Task: review A'),
  ('t2','$H/sessions/t2.jsonl','codex companion task: review B'),
  ('t3','$H/sessions/t3.jsonl','내 작업 세션');
INSERT INTO threads (id,rollout_path,title,is_pinned) VALUES
  ('t4','$H/sessions/t4.jsonl','Codex Companion Task: pinned',1);
INSERT INTO threads (id,rollout_path,title,thread_section_id) VALUES
  ('t5','$H/sessions/t5.jsonl','Codex Companion Task: elsewhere','sec-2');"
sqlite3 "$H/thread_history_1.sqlite" "
CREATE TABLE thread_items (thread_id TEXT, turn_id TEXT, item_id TEXT, PRIMARY KEY (thread_id,turn_id,item_id));
CREATE TABLE thread_turns (thread_id TEXT, turn_id TEXT, PRIMARY KEY (thread_id,turn_id));
CREATE TABLE thread_realtime_items (thread_id TEXT, item_id TEXT, PRIMARY KEY (thread_id,item_id));
INSERT INTO thread_items VALUES ('t1','x','i1'),('t3','x','i1');"
for i in 1 2 3 4 5; do echo '{}' > "$H/sessions/t$i.jsonl"; done
for i in 1 2 3 4 5; do echo "{\"id\":\"t$i\",\"thread_name\":\"n\"}" >> "$H/session_index.jsonl"; done

q() { sqlite3 "$H/state_5.sqlite" "$1"; }
assert() { [ "$2" = "$3" ] || { echo "FAIL $1: expected '$3', got '$2'" >&2; exit 1; }; }

sh "$J" collect >/dev/null
assert "t1,t2 collected"   "$(q "SELECT count(*) FROM threads WHERE thread_section_id='sec-1';")" 2
assert "t3 untouched"      "$(q "SELECT count(*) FROM threads WHERE id='t3' AND thread_section_id IS NULL;")" 1
assert "t4 pinned skipped" "$(q "SELECT count(*) FROM threads WHERE id='t4' AND thread_section_id IS NULL;")" 1
assert "t5 kept in sec-2"  "$(q "SELECT thread_section_id FROM threads WHERE id='t5';")" sec-2

DRY_RUN=1 sh "$J" purge >/dev/null
assert "dry run changes nothing" "$(q "SELECT count(*) FROM threads;")" 5

sh "$J" purge >/dev/null
assert "t1,t2 gone"        "$(q "SELECT count(*) FROM threads WHERE id IN ('t1','t2');")" 0
assert "others remain"     "$(q "SELECT count(*) FROM threads;")" 3
assert "history pruned"    "$(sqlite3 "$H/thread_history_1.sqlite" "SELECT count(*) FROM thread_items WHERE thread_id='t1';")" 0
assert "history kept"      "$(sqlite3 "$H/thread_history_1.sqlite" "SELECT count(*) FROM thread_items WHERE thread_id='t3';")" 1
assert "rollout moved"     "$([ -f "$H/sessions/t1.jsonl" ] && echo yes || echo no)" no
assert "rollout kept"      "$([ -f "$H/sessions/t3.jsonl" ] && echo yes || echo no)" yes
assert "index pruned"      "$(grep -c '"id":"t1"' "$H/session_index.jsonl" || true)" 0
assert "index kept"        "$(grep -c '"id":"t3"' "$H/session_index.jsonl")" 1
assert "trash holds copy"  "$(find "$H/.janitor-trash" -name 't1.jsonl' | wc -l | tr -d ' ')" 1

sh "$J" purge | grep -q 'nothing to delete'
echo "all assertions passed"
