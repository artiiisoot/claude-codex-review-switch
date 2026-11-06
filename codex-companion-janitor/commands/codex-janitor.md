---
description: Codex Companion 세션 수집/삭제 상태 확인과 수동 실행
argument-hint: "[status|collect|purge|install|uninstall] (purge는 --dry-run 가능)"
allowed-tools: Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/janitor.sh:*)
---

`${CLAUDE_PLUGIN_ROOT}/scripts/janitor.sh` 를 실행한다.

인자: `$ARGUMENTS` (없으면 `status`)

- `status` / `collect` / `install` / `uninstall` 은 그대로 실행한다.
- `purge` 는 `--dry-run` 이 붙어 있으면 `DRY_RUN=1 sh .../janitor.sh purge` 로,
  붙어 있지 않으면 먼저 `DRY_RUN=1` 로 돌려 삭제 대상을 사용자에게 보여주고
  확인을 받은 뒤에만 실제 `purge` 를 실행한다.

출력 결과만 간결하게 보고한다.
