#!/bin/sh
# One runnable check: collect moves only matching chats, purge removes them
# and leaves pinned / unrelated / other-section chats alone.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
J="$HERE/../scripts/janitor.sh"
H=$(mktemp -d)
trap 'rm -rf "$H"' EXIT
export CODEX_HOME="$H"

mkdir -p "$H/sessions" "$H/sqlite"
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
# 사이드바 목록은 별도 DB(sqlite/codex.db)의 local_thread_catalog 에서 그려진다.
sqlite3 "$H/sqlite/codex.db" "
CREATE TABLE local_thread_catalog (host_id TEXT NOT NULL, thread_id TEXT NOT NULL,
  display_title TEXT NOT NULL, PRIMARY KEY (host_id, thread_id));
CREATE TABLE local_thread_catalog_scan_entries (host_id TEXT NOT NULL, thread_id TEXT NOT NULL,
  removed INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (host_id, thread_id));
INSERT INTO local_thread_catalog VALUES
  ('local','t1','Codex Companion Task: <task> review A'),
  ('local','t2','codex companion task: <task> review B'),
  ('local','t3','내 작업 세션'),
  ('local','t8','Codex Companion 삭제'),
  ('local','t9','Codex Companion Task: 이미 스레드가 없는 유령 행');"

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
c() { sqlite3 "$H/sqlite/codex.db" "$1"; }
assert "t1,t2 gone"        "$(q "SELECT count(*) FROM threads WHERE id IN ('t1','t2');")" 0
assert "사이드바 행도 삭제" "$(c "SELECT count(*) FROM local_thread_catalog WHERE thread_id IN ('t1','t2');")" 0
assert "유령 행 t9 정리"    "$(c "SELECT count(*) FROM local_thread_catalog WHERE thread_id='t9';")" 0
assert "사이드바 t3 보존"   "$(c "SELECT count(*) FROM local_thread_catalog WHERE thread_id='t3';")" 1
assert "사이드바 t8 보존"   "$(c "SELECT count(*) FROM local_thread_catalog WHERE thread_id='t8';")" 1
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

# 스레드 쪽에 지울 게 없어도 사이드바에만 남은 유령 행은 정리한다.
sqlite3 "$H/sqlite/codex.db" "INSERT INTO local_thread_catalog VALUES
  ('local','t10','Codex Companion Task: 스레드 없는 유령 행');"
assert "유령 행 준비"      "$(c "SELECT count(*) FROM local_thread_catalog WHERE thread_id='t10';")" 1
sh "$J" purge | grep -q 'dropped 1 stale'
assert "유령 행 t10 정리"  "$(c "SELECT count(*) FROM local_thread_catalog WHERE thread_id='t10';")" 0
sh "$J" purge | grep -q 'nothing to delete'

# install 은 plist 를 쓰기 전에 RUN_HOUR 를 검증한다. 잘못된 값이면 기존 예약을
# 덮어쓰지 않고 죽어야 한다.
# launchctl 을 스텁으로 막는다. 막지 않으면 install 이 레이블이 같은 실제
# launchd 작업을 언로드하고 테스트용 경로로 다시 등록해 버린다.
mkdir -p "$H/bin"
printf '#!/bin/sh\nexit 0\n' > "$H/bin/launchctl"; chmod +x "$H/bin/launchctl"
PATH="$H/bin:$PATH"; export PATH
PL="$H/Library/LaunchAgents/com.artiiisoot.codex-companion-janitor.plist"
mkdir -p "$(dirname "$PL")"; echo "기존 예약" > "$PL"
for bad in 25 -1 abc 1e2; do
  RUN_HOUR="$bad" HOME="$H" sh "$J" install 2>&1 | grep -q 'RUN_HOUR must be an integer 0-23' \
    || { echo "FAIL: RUN_HOUR=$bad 가 거부되지 않음" >&2; exit 1; }
done
assert "잘못된 값에 plist 보존" "$(cat "$PL")" "기존 예약"
RUN_HOUR=09 HOME="$H" sh "$J" install >/dev/null 2>&1
assert "앞자리 0 허용"          "$(grep -c '<integer>9</integer>' "$PL")" 2

# 섹션이 없으면 collect 가 직접 만든다 (설치 직후 수동 준비가 필요 없게).
H2=$(mktemp -d); trap 'rm -rf "$H" "$H2"' EXIT
mkdir -p "$H2/sessions" "$H2/sqlite"
sqlite3 "$H2/state_5.sqlite" "
CREATE TABLE thread_sections (id TEXT PRIMARY KEY, name TEXT NOT NULL, appearance TEXT);
CREATE TABLE threads (id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL, title TEXT NOT NULL,
  name TEXT, archived INTEGER NOT NULL DEFAULT 0, is_pinned INTEGER NOT NULL DEFAULT 0,
  thread_section_id TEXT, section_entered_at_ms INTEGER);
INSERT INTO threads (id,rollout_path,title,name) VALUES
  ('a1','$H2/sessions/a1.jsonl','<task> x','Codex Companion Task: <task> x');"
q2() { sqlite3 "$H2/state_5.sqlite" "$1"; }
assert "섹션 없음 확인"   "$(q2 "SELECT count(*) FROM thread_sections;")" 0
CODEX_HOME="$H2" sh "$J" collect >/dev/null 2>&1
assert "섹션 자동 생성"   "$(q2 "SELECT name FROM thread_sections;")" "Codex Companion"
assert "생성 후 수집"     "$(q2 "SELECT count(*) FROM threads WHERE thread_section_id IS NOT NULL;")" 1

# 훅은 세션마다 돈다: 여러 번 돌아도 같은 이름의 섹션이 하나뿐이어야 한다.
for _ in 1 2 3; do CODEX_HOME="$H2" sh "$J" collect >/dev/null 2>&1; done
assert "섹션 중복 없음"   "$(q2 "SELECT count(*) FROM thread_sections WHERE name='Codex Companion';")" 1
# 동시 실행도 한 개만 남아야 한다.
sqlite3 "$H2/state_5.sqlite" "DELETE FROM thread_sections; UPDATE threads SET thread_section_id=NULL;"
for _ in 1 2 3 4 5; do CODEX_HOME="$H2" sh "$J" collect >/dev/null 2>&1 & done
wait
assert "동시 실행도 하나" "$(q2 "SELECT count(*) FROM thread_sections WHERE name='Codex Companion';")" 1

# 잘못된 RUN_HOUR 는 섹션도 만들지 않고 죽어야 한다.
sqlite3 "$H2/state_5.sqlite" "DELETE FROM thread_sections;"
RUN_HOUR=99 CODEX_HOME="$H2" HOME="$H" sh "$J" install >/dev/null 2>&1 || true
assert "검증 실패 시 무변경" "$(q2 "SELECT count(*) FROM thread_sections;")" 0

echo "all assertions passed"
