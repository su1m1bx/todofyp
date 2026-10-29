# Todo List

해야 할 일을, 눈에 보이는 곳에. Mac을 위한 작은 플로팅 투두 리스트입니다.

**[다운로드](https://github.com/su1m1bx/todofyp/releases)** · [문제 제보](https://github.com/su1m1bx/todofyp/issues)

macOS 26 이상 · Apple Silicon

## 특징

- **작업 흐름 그대로** — 작은 창에서 할 일을 확인하고, 메뉴 막대에서 바로 숨기거나 다시 표시합니다.
- **중요한 일부터** — 빠른 입력, 드래그 정렬, 기한과 카테고리로 정리합니다.
- **메모까지 함께** — 상세 메모와 굵게·기울임·밑줄, 삭제 후 5초 실행 취소를 지원합니다.
- **Mac에 어울리는 모습** — 유리 소재 UI, 시스템/라이트/다크 모드, 배경 색상·이미지를 제공합니다.
- **내 Mac에만 저장** — 계정, 서버, 분석 수집 없이 오프라인으로 사용합니다.

## 설치

1. **[Releases](https://github.com/su1m1bx/todofyp/releases)**에서 `.dmg` 파일을 다운로드합니다.
2. DMG를 열고 **`Important Todo.app`을 `Applications`로 드래그**합니다.
3. **응용 프로그램** 폴더에서 앱을 실행합니다.

Releases에 `.dmg`가 없다면 아직 배포 전입니다. `Source code (zip)`은 설치 파일이 아닙니다.

### 처음 실행할 때 차단된다면

현재 앱은 **Developer ID 서명·Apple 공증이 완료되지 않은 테스트 빌드**입니다. 출처를 신뢰하는 경우에만 실행하세요.

앱 실행을 시도한 뒤 **시스템 설정 → 개인정보 보호 및 보안 → 확인 없이 열기**를 선택합니다.

<details>
<summary>터미널로 해당 앱만 허용하기</summary>

응용 프로그램 폴더에 설치한 뒤 실행하세요.

```sh
xattr -dr com.apple.quarantine "/Applications/Important Todo.app"
open "/Applications/Important Todo.app"
```

지정한 앱의 격리 속성만 제거하며, 안전성을 검증하거나 공증하지는 않습니다. macOS 전체 보안을 끄거나 악성 코드 경고를 우회하지 마세요.

</details>

## 사용법

- **추가:** 입력 후 `Enter`. **순서 변경:** 드래그 또는 `⌥↑` / `⌥↓`.
- **상세 편집:** 제목 더블클릭. **메모 서식:** `⌘B` / `⌘I` / `⌘U`.
- **표시·숨김:** 메뉴 막대 아이콘 클릭. **설정·종료:** 아이콘 보조 클릭.
- 아이콘이 보이지 않으면 응용 프로그램에서 앱을 다시 실행해 기존 창을 복구하세요.

> 전체 화면·Spaces·Stage Manager의 모든 조합은 아직 검증되지 않았습니다. 잠금 화면·시스템 보안 UI 위 표시는 보장하지 않습니다.

<details>
<summary>소스에서 빌드하기</summary>

Swift 6 도구 체인과 macOS 26 이상 SDK가 필요합니다. 외부 패키지 의존성은 없습니다.

```sh
swift test
bash scripts/build.sh
open "dist/Important Todo.app"
```

DMG 생성: `bash scripts/package.sh`. 산출물은 `dist/`에 생성되며 기본 서명은 로컬 ad-hoc입니다.

</details>
