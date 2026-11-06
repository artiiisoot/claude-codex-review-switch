# codex-companion-janitor

Codex CLI에 쌓이는 `Codex Companion Task:` 세션을 매일 자동으로 정리합니다.

- **18:00** — 섹션에 남아 있는 세션을 먼저 지우고, 기본 Tasks/chats에 있는 `Codex Companion Task:` 세션을 사이드바의 **Codex Companion** 섹션으로 옮깁니다.
- **18:10** — 그 섹션에 있는 `Codex Companion Task:` 세션을 삭제합니다.

18:00에도 삭제를 먼저 돌리기 때문에, 맥이 꺼져 있거나 잠들어서 18:10을 놓쳤을 때 남은 세션이 다음 날 수집 전에 정리됩니다.

## 삭제 범위

세션 하나당 다음을 지웁니다.

- `~/.codex/sessions/.../rollout-*.jsonl` (rollout 파일)
- `state_*.sqlite`의 `threads`, `thread_attachments`, `thread_read_receipts`, `thread_spawn_edges` 행
- `thread_history_*.sqlite`의 `thread_items`, `thread_turns`, `thread_realtime_items` 행
- `~/.codex/session_index.jsonl`의 해당 줄

지우기 전에 rollout 파일과 두 DB 사본을 `~/.codex/.janitor-trash/<타임스탬프>/`로 옮겨 두고, `TRASH_DAYS`(기본 7일)이 지난 폴더는 다음 실행에서 정리합니다.

**건드리지 않는 것**: 고정(pin)된 세션, 제목이 다른 세션, 사용자가 다른 섹션으로 옮긴 세션, archive된 세션.

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
- Codex 앱 사이드바에 **Codex Companion** 섹션이 이미 있어야 합니다. 없으면 임의로 만들지 않고 오류를 냅니다.

## 환경 변수

| 변수 | 기본값 | 설명 |
|---|---|---|
| `CODEX_HOME` | `~/.codex` | Codex 데이터 폴더 |
| `SECTION_NAME` | `Codex Companion` | 대상 섹션 이름 |
| `TITLE_PREFIX` | `Codex Companion Task:` | 수집/삭제 대상 제목 접두사 |
| `TRASH_DAYS` | `7` | 휴지통 보관 일수 |
| `DRY_RUN` | — | `1` 이면 purge가 삭제 대상만 출력 |
| `FAKE_MINUTE` | — | `run`이 분기하는 분을 덮어씀 (테스트용) |

## 주의

- Codex 앱이 **실행 중**이면 UI가 이미 읽어 둔 목록과 어긋날 수 있습니다. 삭제 직후 Codex를 다시 켜면 맞춰집니다.
- 기존 Codex 자동화(`~/.codex/automations/codex-companion`)가 같은 18:00 수집을 하고 있으면 둘 중 하나만 두세요.

## 테스트

```bash
sh tests/janitor.test.sh
```

## 라이선스

MIT
