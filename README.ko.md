# SMCController

Intel 및 Apple Silicon Mac에서 SMC 기반 팬 제어를 다루기 위한 SwiftUI 기반 macOS 앱입니다.

[English README](README.md)

## 개요

SMCController는 다음 작업을 데스크톱 UI로 제공합니다.

- 온도, 팬 RPM, 일부 전력 지표 모니터링
- 사용자 지정 팬 커브 편집
- 필요할 경우 PID 값으로 팬 제어 보정
- 프리셋 저장 및 불러오기
- 실제로 팬 쓰기 제어가 필요할 때만 helper daemon 설치 또는 실행

일반 모니터링 중에는 앱이 비권한 상태로 동작합니다. 권한이 필요한 helper daemon은 `Privileges` 화면에서 직접 활성화하거나, 팬 제어에 실제로 필요한 경로를 실행할 때만 설치 또는 시작됩니다.

## 현재 기능

### 팬 제어

- 그래프 + 포인트 목록 기반 팬 커브 편집
- 하드웨어에서 최소/최대 RPM 다시 읽기
- 감지된 팬 개수에 맞춘 동적 fan index 선택
- 목표 온도, `Kp`, `Ki`, `Kd` 기반 선택적 PID 튜닝
- 모니터링 전용 모드와 실제 제어 모드

### 안전 장치

- 임계 온도 설정(기본 100 °C, 70–110 °C): 도달하면 수동 제어를 멈추고 macOS가 팬을 제어
- 비정상 센서 값(0 °C 고정, 150 °C 초과)은 센서 읽기 실패와 같이 처리해 수동 제어 중지
- 팬 속도는 즉시 올리고, 내릴 때는 온도가 2 °C 이상 떨어진 뒤 초당 최대 100 RPM씩만 감소
- Mac이 잠자기에 들어가기 전에 자동 모드로 복원하고, 깨어난 뒤 5초 후 제어 재개
- 앱 종료 시 자동 모드를 먼저 복원(최대 3초, 나머지는 헬퍼 lease 워치독이 처리)

### 모니터링

- 현재 온도와 적용 RPM 표시
- 추가 SMC 센서 키 모니터링
- Apple Silicon HID 센서 진단 화면
- SMC 센서 진단 화면
- 가능할 경우 daemon 기반 power metrics 조회

### 메뉴 막대와 실행

- 메뉴 막대에 현재 온도와 팬 RPM 표시, 시작/중지, 프리셋 전환, 종료
- 로그인 시 실행(macOS 로그인 항목)
- 실행 시 모니터링 시작, 실행 시 팬 제어 재개(헬퍼가 이미 활성화된 경우에만, 권한 요청 없음) 선택 가능
- 팬 제어가 스스로 멈추면(과열, 센서 또는 쓰기 실패) 알림

### 기록

- 최근 10분간의 온도와 팬 RPM 그래프, 온도가 임계값에 가까워지면 임계선 표시

### 프리셋 및 설정 저장

- 마지막으로 사용한 설정 자동 복원
- 이름 있는 프리셋 저장, 불러오기, 갱신, 삭제
- 프리셋 JSON 내보내기/가져오기(같은 이름의 프리셋은 덮어씀)
- 팬 제어 중에 프리셋을 불러오면 즉시 적용
- 커브 포인트, PID 값, 센서 키, fan index, interval 저장

### 권한 흐름

- 첫 실행 시 자동 권한 프롬프트 없음
- helper 설치 및 실행 상태 확인 화면 제공
- 수동 팬 제어가 필요할 때 한 번의 버튼으로 helper 활성화

## 앱 탐색 구조

현재 사이드바 구성은 다음과 같습니다.

- `Fan Control`
- `Privileges`
- `Presets`
- `Diagnostics`
  - `HID Sensors`
  - `SMC Sensors`

`About` 화면은 사이드바가 아니라 macOS 앱 메뉴에서 열 수 있습니다.

## 프로젝트 구조

```text
SMCController/
├── App/                # 앱 진입점, 루트 내비게이션, 에셋
├── Core/
│   ├── Controllers/    # 팬 제어 루프 및 제어 중심 API
│   ├── Models/         # 공용 데이터/정책 타입
│   └── Services/       # helper, sensor, daemon, 시스템 연동 서비스
├── Features/
│   ├── About/
│   ├── Diagnostics/
│   ├── FanControl/
│   ├── Presets/
│   └── Privileges/
├── Platform/           # SMC/HID 브리지 및 저수준 플랫폼 연동
└── Support/            # 다국어 및 앱 언어 설정 헬퍼
```

## 요구 사항

- macOS 14 이상
- Xcode 15 이상
- 필요한 SMC 또는 HID 데이터 경로를 노출하는 Mac
- 권한이 필요한 팬 제어를 사용하려면 로컬 관리자 계정

## 빌드 및 실행

### 1. helper 리소스 준비

이 앱은 `DaemonClient`가 사용하는 다음 번들 리소스를 기대합니다.

- `SMCHelper`
- `install_helper`
- `com.minepacu.SMCHelper.plist`

소스에서 빌드하는 경우, 권한이 필요한 팬 제어를 사용하려면 위 리소스를 먼저 준비해서 앱 번들에 포함해야 합니다.

### 2. Xcode에서 열고 빌드

- `SMCController.xcodeproj`를 Xcode에서 엽니다.
- 기본 스킴으로 빌드합니다.

### 3. 실행

- 일반 권한으로 앱을 실행합니다.
- 모니터링 기능은 추가 권한 없이 동작할 수 있습니다.
- 팬 쓰기 제어가 필요하면 `Privileges` 화면에서 `Enable Fan Control`을 사용합니다.

## 일반적인 사용 흐름

1. `Fan Control`을 엽니다.
2. 팬 커브 기준이 될 센서 키를 선택합니다.
3. 필요하면 최소/최대 RPM을 다시 읽습니다.
4. 커브 포인트를 조정합니다.
5. 필요하면 PID 튜닝을 활성화합니다.
6. 현재 구성을 프리셋으로 저장합니다.
7. 수동 팬 제어가 필요하면 `Privileges`에서 helper를 활성화합니다.
8. 실제 팬 제어를 시작하거나 모니터링 전용으로 사용합니다.

## 주의 사항

- 수동 팬 제어는 시스템 기본 열 관리 정책을 덮어쓸 수 있습니다.
- Apple Silicon에서의 팬 제어 지원은 하드웨어 노출 방식과 helper 상태에 따라 달라집니다.
- 센서 값이나 팬 동작이 이상하면 제어를 중지하고 자동 모드로 되돌리는 것이 안전합니다.
- 센서 가용성은 Mac 모델마다 다릅니다.

## 주요 소스 위치

- [SMCController/App/ContentView.swift](SMCController/App/ContentView.swift)
- [SMCController/App/SMCControllerApp.swift](SMCController/App/SMCControllerApp.swift)
- [SMCController/Features/FanControl/FanControlView.swift](SMCController/Features/FanControl/FanControlView.swift)
- [SMCController/Features/FanControl/FanControlViewModel.swift](SMCController/Features/FanControl/FanControlViewModel.swift)
- [SMCController/Features/Privileges/PrivilegeStatusView.swift](SMCController/Features/Privileges/PrivilegeStatusView.swift)
- [SMCController/Core/Services/DaemonClient.swift](SMCController/Core/Services/DaemonClient.swift)
- [SMCController/Platform/SMC.swift](SMCController/Platform/SMC.swift)

## 라이선스

MIT 라이선스로 배포됩니다. 자세한 내용은 [LICENSE](LICENSE)를 참고하세요.
