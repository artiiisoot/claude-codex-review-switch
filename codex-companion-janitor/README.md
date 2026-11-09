# codex-companion-janitor

Codex CLI에 쌓이는 `Codex Companion Task:` 세션을 자동으로 모으고 정리합니다.

- **리뷰가 끝날 때마다** — Stop/SessionEnd 훅이 `collect`를 돌려 새 `Codex Companion Task:` 세션을 **Codex Companion** 섹션으로 옮깁니다. 섹션이 없으면 만듭니다.
- **매일 09:10** — 그 섹션에 있는 세션을 삭제합니다.

수집은 훅만 합니다. 예약 작업은 삭제만 합니다.

훅은 리뷰를 띄운 턴의 바로 다음 턴에 그 세션을 잡습니다. Codex가 세션 이름을 붙이는 시점이 리뷰 실행과 맞물려 있어서, 같은 턴에 못 잡으면 다음 턴에 들어갑니다.

시각은 `RUN_HOUR`로 바꿉니다. plist에 구워지므로 바꾼 뒤 `install`을 다시 실행해야 합니다.

```bash
RUN_HOUR=18 sh scripts/janitor.sh install
```

`RUN_HOUR`가 0–23의 정수가 아니면 `install`은 아무것도 건드리지 않고 중단합니다.

맥이 그 시각에 꺼져 있으면 launchd는 건너뛴 실행을 부팅 후 따라잡지 않습니다. 다음 실행 때 밀린 세션까지 한꺼번에 지워집니다.

## 삭제 범위

세션 하나당 다음을 지웁니다.

- `~/.codex/sessions/.../rollout-*.jsonl` (rollout 파일)
- `state_*.sqlite`의 `threads`, `thread_attachments`, `thread_read_receipts`, `thread_spawn_edges` 행
- `thread_history_*.sqlite`의 `thread_items`, `thread_turns`, `thread_realtime_items` 행
- `~/.codex/session_index.jsonl`의 해당 줄
- `~/.codex/sqlite/codex.db`의 `local_thread_catalog`, `local_thread_catalog_scan_entries` 행 — **사이드바 목록은 이 테이블에서 그려집니다.** 여기를 지우지 않으면 앱을 다시 켜도 목록이 남습니다.

스레드가 이미 다른 경로로 사라졌는데 사이드바에만 남은 "유령 행"도 같이 정리합니다. `status`의 `stale rows`가 그 개수입니다.

지우기 전에 rollout 파일과 두 DB 사본을 `~/.codex/.janitor-trash/<타임스탬프>/`로 옮겨 두고, `TRASH_DAYS`(기본 7일)이 지난 폴더는 다음 실행에서 정리합니다.

훅은 리뷰를 띄운 턴의 바로 다음 턴에 그 세션을 잡습니다. Codex가 세션 이름을 붙이는 시점이 리뷰 실행과 맞물려 있어서, 같은 턴에 못 잡으면 다음 턴에 들어갑니다.

**건드리지 않는 것**: 고정(pin)된 세션, 이름이 다른 세션, 사용자가 다른 섹션으로 옮긴 세션, archive된 세션.

판정은 사이드바에 보이는 이름(`threads.name`)으로만 합니다. 첫 사용자 메시지(`threads.title`)는 보지 않으므로, "codex companion task: …" 라고 물어본 본인 대화는 대상이 되지 않습니다.

## 설치

```
/plugin install codex-companion-janitor --marketplace artiiisoot/claude-codex-review-switch
```

스케줄은 한 번만 직접 등록합니다 (launchd, macOS):

```bash
sh ~/.claude/plugins/.../codex-companion-janitor/scripts/janitor.sh install
```

경로는 `/codex-janitor status`가 알려줍니다. `uninstall`로 해제합니다.

## 사용

```
/codex-janitor status
/codex-janitor purge --dry-run
```

셸에서 직접:

```bash
sh scripts/janitor.sh status
```

## 필요한 것

- macOS (`launchd`), `sh`, `sqlite3`
- `uuidgen` (macOS 기본 내장) — 섹션을 만들 때 씁니다. **Codex Companion** 섹션은 `install` 이나 첫 `collect` 때 없으면 자동으로 만들어집니다.

## 환경 변수

| 변수 | 기본값 | 설명 |
|---|---|---|
| `CODEX_HOME` | `~/.codex` | Codex 데이터 폴더 |
| `SECTION_NAME` | `Codex Companion` | 대상 섹션 이름 |
| `TITLE_PREFIX` | `Codex Companion Task:` | 수집/삭제 대상 이름(`threads.name`) 접두사 |
| `TRASH_DAYS` | `7` | 휴지통 보관 일수 |
| `RUN_HOUR` | `9` | 삭제 시각(시, 0–23). `install` 때 plist에 기록됨 |
| `DRY_RUN` | — | `1`이면 purge가 삭제 대상만 출력 |

## 주의

- Codex 앱이 **실행 중**이면 UI가 이미 읽어 둔 목록과 어긋날 수 있습니다. 삭제 직후 Codex를 다시 켜면 맞춰집니다.
- 기존 Codex 자동화(`~/.codex/automations/codex-companion`)가 같은 18:00 수집을 하고 있으면 둘 중 하나만 두세요.

## 테스트

```bash
sh tests/janitor.test.sh
```

## 라이선스

MIT
