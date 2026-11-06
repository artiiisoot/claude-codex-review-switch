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
  name TEXT, archived INTEGER NOT NULL DEFAULT 0, is_pinned INTEGER NOT NULL DEFAULT 0,
  thread_section_id TEXT, section_entered_at_ms INTEGER);
CREATE TABLE thread_attachments (id TEXT PRIMARY KEY, thread_id TEXT NOT NULL);
CREATE TABLE thread_read_receipts (thread_id TEXT PRIMARY KEY, revision TEXT NOT NULL DEFAULT '');
CREATE TABLE thread_spawn_edges (parent_thread_id TEXT, child_thread_id TEXT PRIMARY KEY, status TEXT);
INSERT INTO thread_sections VALUES ('sec-1','Codex Companion',NULL),('sec-2','Pinned',NULL);
INSERT INTO threads (id,rollout_path,title,name) VALUES
  ('t1','$H/sessions/t1.jsonl','<task> review A','Codex Companion Task: <task> review A'),
  ('t2','$H/sessions/t2.jsonl','<task> review B','codex companion task: <task> review B'),
  ('t3','$H/sessions/t3.jsonl','내 작업 세션','내 작업 세션'),
  ('t8','$H/sessions/t8.jsonl','codex companion task: 이 세션들 어떻게 지워?','Codex Companion 삭제');
INSERT INTO threads (id,rollout_path,title,name,is_pinned) VALUES
  ('t4','$H/sessions/t4.jsonl','<task> pinned','Codex Companion Task: pinned',1);
INSERT INTO threads (id,rollout_path,title,name,thread_section_id) VALUES
  ('t5','$H/sessions/t5.jsonl','<task> elsewhere','Codex Companion Task: elsewhere','sec-2');"
sqlite3 "$H/thread_history_1.sqlite" "
CREATE TABLE thread_items (thread_id TEXT, turn_id TEXT, item_id TEXT, PRIMARY KEY (thread_id,turn_id,item_id));
CREATE TABLE thread_turns (thread_id TEXT, turn_id TEXT, PRIMARY KEY (thread_id,turn_id));
CREATE TABLE thread_realtime_items (thread_id TEXT, item_id TEXT, PRIMARY KEY (thread_id,item_id));
INSERT INTO thread_items VALUES ('t1','x','i1'),('t3','x','i1');"
for i in 1 2 3 4 5 8; do echo '{}' > "$H/sessions/t$i.jsonl"; done
for i in 1 2 3 4 5 8; do echo "{\"id\":\"t$i\",\"thread_name\":\"n\"}" >> "$H/session_index.jsonl"; done

q() { sqlite3 "$H/state_5.sqlite" "$1"; }
assert() { [ "$2" = "$3" ] || { echo "FAIL $1: expected '$3', got '$2'" >&2; exit 1; }; }

sh "$J" collect >/dev/null
assert "t1,t2 collected"   "$(q "SELECT count(*) FROM threads WHERE thread_section_id='sec-1';")" 2
assert "t3 untouched"      "$(q "SELECT count(*) FROM threads WHERE id='t3' AND thread_section_id IS NULL;")" 1
assert "t4 pinned skipped" "$(q "SELECT count(*) FROM threads WHERE id='t4' AND thread_section_id IS NULL;")" 1
assert "t5 kept in sec-2"  "$(q "SELECT thread_section_id FROM threads WHERE id='t5';")" sec-2
# 사이드바 이름(name)이 아니라 첫 메시지(title)만 맞는 사용자 채팅은 건드리지 않는다.
assert "t8 user chat safe" "$(q "SELECT count(*) FROM threads WHERE id='t8' AND thread_section_id IS NULL;")" 1

DRY_RUN=1 sh "$J" purge >/dev/null
assert "dry run changes nothing" "$(q "SELECT count(*) FROM threads;")" 6

sh "$J" purge >/dev/null
assert "t1,t2 gone"        "$(q "SELECT count(*) FROM threads WHERE id IN ('t1','t2');")" 0
assert "others remain"     "$(q "SELECT count(*) FROM threads;")" 4
assert "t8 still there"    "$(q "SELECT count(*) FROM threads WHERE id='t8';")" 1
assert "history pruned"    "$(sqlite3 "$H/thread_history_1.sqlite" "SELECT count(*) FROM thread_items WHERE thread_id='t1';")" 0
assert "history kept"      "$(sqlite3 "$H/thread_history_1.sqlite" "SELECT count(*) FROM thread_items WHERE thread_id='t3';")" 1
assert "rollout moved"     "$([ -f "$H/sessions/t1.jsonl" ] && echo yes || echo no)" no
assert "rollout kept"      "$([ -f "$H/sessions/t3.jsonl" ] && echo yes || echo no)" yes
assert "index pruned"      "$(grep -c '"id":"t1"' "$H/session_index.jsonl" || true)" 0
assert "index kept"        "$(grep -c '"id":"t3"' "$H/session_index.jsonl")" 1
assert "trash holds copy"  "$(find "$H/.janitor-trash" -name 't1.jsonl' | wc -l | tr -d ' ')" 1

sh "$J" purge | grep -q 'nothing to delete'

# run at :00 purges leftovers from a missed 18:10 first, then collects today's batch.
sqlite3 "$H/state_5.sqlite" "
INSERT INTO threads (id,rollout_path,title,name,thread_section_id) VALUES
  ('t6','$H/sessions/t6.jsonl','<task> leftover','Codex Companion Task: leftover','sec-1');
INSERT INTO threads (id,rollout_path,title,name) VALUES
  ('t7','$H/sessions/t7.jsonl','<task> fresh','Codex Companion Task: fresh');"
echo '{}' > "$H/sessions/t6.jsonl"; echo '{}' > "$H/sessions/t7.jsonl"
FAKE_MINUTE=0 sh "$J" run >/dev/null
assert "leftover purged"   "$(q "SELECT count(*) FROM threads WHERE id='t6';")" 0
assert "fresh collected"   "$(q "SELECT thread_section_id FROM threads WHERE id='t7';")" sec-1

# run at :10 only purges.
FAKE_MINUTE=10 sh "$J" run >/dev/null
assert "fresh purged"      "$(q "SELECT count(*) FROM threads WHERE id='t7';")" 0
assert "survivors intact"  "$(q "SELECT count(*) FROM threads;")" 4

echo "all assertions passed"
