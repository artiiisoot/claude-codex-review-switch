# codex-review-switch

Claude Code에서 **Codex 리뷰 게이트**를 입력창 위 토글 스위치로 켜고 끄는 모드입니다.
대화에서는 Claude와 Codex의 답변을 색과 아이콘으로 구분합니다.

## 기능

- **입력창 위 토글 스위치**: `◆ Codex 리뷰` 옆 스위치로 현재 프로젝트(git 루트)의 stop-time 리뷰 게이트를 켜고 끕니다. 데스크톱 앱에서는 macOS 스타일 토글, 터미널에서는 글자 스위치로 그립니다.
- **Claude 표시**: Claude 답변 맨 위에 주황색 `✻ Claude`를 붙입니다.
- **Codex 리뷰 결과**: 게이트가 켜져 있으면 답변이 끝날 때 Codex가 리뷰한 결과를, 리뷰한 답변 아래 초록 테두리 상자에 남깁니다.
  - `✓ 지적 사항 없음`: 통과해도 결과를 남깁니다.
  - `✗ 지적 있음`: 지적 내용을 보여주고, Claude가 이어서 수정합니다.
  - `! 리뷰 실행 실패`: 리뷰가 실패한 이유를 보여줍니다.
- `/codex-review-switch`: 게이트 상태를 다시 읽어 알려줍니다.

## 필요한 것

- [Codex 플러그인](https://github.com/openai/codex-plugin-cc) (`codex@openai-codex`)이 설치되어 있어야 합니다. 리뷰 자체는 이 플러그인의 Stop 훅이 실행하고, 이 모드는 스위치와 결과 표시를 맡습니다.
- Codex CLI 설치와 로그인: Claude Code에서 `/codex:setup`을 실행해 확인하세요.
- macOS 또는 Linux (`/bin/sh`와 `node`를 씁니다).

## 설치

터미널의 Claude Code 프롬프트에서:

```
/plugin install codex-review-switch --marketplace artiiisoot/claude-codex-review-switch
```

셸에서:

```bash
claude plugin install codex-review-switch --marketplace artiiisoot/claude-codex-review-switch
```

데스크톱 앱에서는 `/plugin`이 동작하지 않습니다. 프롬프트 옆 `+` → Plugins → Add marketplace에 `artiiisoot/claude-codex-review-switch`를 넣고 Add plugin을 누르세요.

설치 후 새 세션부터 적용됩니다.

## 주의

- 게이트를 켜면 **답변이 끝날 때마다** Codex 리뷰가 실행됩니다. 답변마다 최대 15분이 더 걸릴 수 있고 Codex 사용량이 듭니다.
- 스위치는 프로젝트(git 루트)마다 따로 저장됩니다.
- Codex 결과는 리뷰한 답변의 글로 짝을 찾기 때문에, 아주 짧은 같은 답변이 반복되면 앞의 답변에도 결과 상자가 보일 수 있습니다.

## 라이선스

MIT
