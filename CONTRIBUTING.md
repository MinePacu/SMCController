# Contributing to SMCController

SMCController 프로젝트에 기여해 주셔서 감사합니다! 이 문서는 프로젝트에 효과적으로 기여하기 위한 가이드를 제공합니다.

## 행동 강령 (Code of Conduct)

모든 기여자는 서로를 존중하고 건설적인 태도로 소통해야 합니다. 괴롭힘, 차별, 비방 행위는 허용되지 않습니다.

## 기여 방법

### 이슈 보고

버그를 발견하거나 새로운 기능을 제안하고 싶다면 [이슈 트래커](https://gitlab.com/minepacu-group/SMCController/-/issues)에 이슈를 등록해 주세요.

이슈를 등록할 때는 다음 정보를 포함해 주세요:

- **버그 보고**
  - 재현 가능한 단계
  - 예상 동작과 실제 동작
  - 사용 중인 macOS 버전과 하드웨어 정보
  - 관련 로그 또는 스크린샷
- **기능 제안**
  - 해결하고자 하는 문제
  - 제안하는 해결 방안
  - 대안이나 참고 자료

### 머지 리퀘스트(MR) 워크플로우

1. 이슈를 먼저 생성하거나 기존 이슈를 확인합니다.
2. 저장소를 포크하거나 새로운 브랜치를 생성합니다.
   - 브랜치 이름은 `feature/`, `fix/`, `docs/`, `refactor/` 등의 접두사를 사용해 주세요.
3. 변경 사항을 커밋합니다. (커밋 메시지 규칙은 아래 참고)
4. 원격 브랜치에 푸시한 후 머지 리퀘스트를 생성합니다.
5. MR 설명에 관련 이슈 번호(`Closes #<번호>`)를 포함해 주세요.
6. 리뷰어의 피드백을 반영합니다.

## 개발 환경 설정

### 요구 사항

- macOS (Apple Silicon 또는 Intel)
- Xcode 최신 안정 버전
- Swift 5.x 이상

### 빌드 및 테스트

저장소 루트에서 제공되는 스크립트를 사용할 수 있습니다:

```bash
./build_and_test.sh
```

또는 Xcode에서 `SMCController.xcodeproj`를 열어 빌드 및 테스트를 진행할 수 있습니다.

## 코딩 스타일

- **Swift**: [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)를 따릅니다.
- **C / Objective-C**: 기존 코드 스타일을 유지합니다.
- **들여쓰기**: 스페이스 4칸을 기본으로 합니다.
- **네이밍**: 명확하고 의도가 드러나는 이름을 사용합니다.
- 가능한 한 새로운 의존성을 추가하지 않습니다.

## 커밋 메시지 규칙

[Conventional Commits](https://www.conventionalcommits.org/) 형식을 권장합니다.

```
<type>(<scope>): <subject>

<body>

<footer>
```

주요 타입:

- `feat`: 새로운 기능 추가
- `fix`: 버그 수정
- `docs`: 문서 변경
- `style`: 코드 스타일 변경 (동작에 영향 없음)
- `refactor`: 리팩터링
- `test`: 테스트 추가/수정
- `chore`: 빌드, 설정 등 기타 변경

예시:

```
feat(helper): add fan speed control API

fix(ui): correct temperature unit display
```

## 테스트

- 새로운 기능을 추가할 때는 가능한 한 단위 테스트 또는 UI 테스트를 함께 작성해 주세요.
- 기존 테스트가 모두 통과하는지 확인 후 MR을 제출해 주세요.

## 라이선스

이 프로젝트에 기여하는 모든 코드는 프로젝트의 [LICENSE](LICENSE) (MIT License)에 따라 배포됨에 동의하는 것으로 간주합니다.

## 문의

추가 질문이 있다면 이슈 트래커를 통해 문의해 주세요.
