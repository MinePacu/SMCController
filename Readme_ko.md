# SMCController

macOS에서 SMC를 통해 팬을 제어하는 SwiftUI 앱입니다. Apple Silicon/Intel 모두 지원하며, 사용자 커브/센서 모니터링/PID 보정을 제공하고 권한이 필요한 작업은 번들에 포함된 SMCHelper 데몬이 수행합니다.

## 주요 기능
- 팬 커브 에디터 + PID 보정: 온도/RPM 포인트를 그래프·테이블로 편집하고 실행 중에도 `Apply`로 즉시 반영
- 센서 모니터링: CPU/GPU/팬 RPM, SMC 센서 디버그, Apple Silicon HID 센서 디버그 뷰 제공
- 권한 처리: Authorization Services로 번들 내 SMCHelper를 `/Library/PrivilegedHelperTools/com.minepacu.SMCHelper`에 설치하고 Unix 소켓(`/tmp/com.minepacu.SMCHelper.socket`)으로 통신
- 운영 편의: 모니터링 전용 모드, 하드웨어 min/max RPM 자동 로드, 팬 인덱스 선택, 추가 센서 키 모니터링
- 스크립트 지원: `build_and_test.sh`, `check_daemon.sh`, `cleanup_daemon.sh` 등으로 빌드/상태 확인/정리

## 구성
- SwiftUI 앱 (`SMCController/`): UI, `FanController` 루프, `FanPolicy`·`FanCurveEditorView` 등 로직
- SMC/HID 브릿지 (`SMCBridge.c`, `SMCHID.m`, `SMCAppleSilicon.swift`): 하드웨어 직접 호출
- 특권 데몬 (`SMCHelper/main_daemon.c`) & 설치 도구(`install_helper.c`): 번들에서 복사되어 LaunchDaemon으로 실행
- 권한 헬퍼 (`DaemonClient.swift`, `PrivilegeHelper.swift`): 데몬 설치/실행 및 권한 체크

## 요구 사항
- macOS 14+ / Xcode 15+ (Swift Observation 사용)
- 로컬 관리자 계정: 최초 데몬 설치 시 비밀번호 1회 필요
- 빌드 도구: Xcode command line tools, clang

## 빠른 시작 (소스 빌드)
1) SMCHelper 번들 파일 생성  
```bash
cd SMCHelper
./prepare_bundle.sh
```
→ `SMCHelper`, `install_helper`, `com.minepacu.SMCHelper.plist` 생성

2) Xcode에 리소스 포함  
- `File → Add Files...`로 위 3개 파일을 추가 (Copy items if needed, Target: SMCController).  
- `Build Phases → Copy Bundle Resources`에 포함됐는지 확인하고 `Compile Sources`에는 넣지 않습니다.  
- 상세: `BUILD_AND_TEST.md`, `PREBUILT_BINARY_INSTALL.md`

3) 빌드  
- Xcode: `Product → Clean Build Folder` 후 `Build`  
- CLI: `./build_and_test.sh` (코드 서명 없이 Release 빌드)

4) 실행  
- 빌드된 `SMCController.app`을 실행 (`build/Build/Products/Release/SMCController.app` 또는 Xcode Run).  
- 팬 제어를 시작하면 Authorization Services 비밀번호 프롬프트가 뜨며 데몬이 `/Library/PrivilegedHelperTools/com.minepacu.SMCHelper`에 설치됩니다.

5) 확인  
```bash
./check_daemon.sh
```

## 사용법
- 앱은 **일반 권한**으로 실행합니다 (sudo 불필요). 데몬이 없는 경우 자동 설치를 시도합니다.
- Fan Control 탭:  
  - 센서 키: Intel은 `TC0P`, Apple Silicon은 자동 감지(`Tp09`) 기본. 추가 모니터링 키를 쉼표로 입력.  
  - 팬 인덱스와 Min/Max RPM은 하드웨어에서 읽어오며 `Refresh Fan Limits`로 갱신.  
  - 커브 동작: 포인트 사이를 선형 보간, 최저 온도 미만은 Min RPM, 최고 온도 초과는 Max RPM. 포인트는 최소 2개, 최대 12개 권장.  
  - PID: 선택 사항. Target은 선호하는 CPU 온도(예: 70°C) 부근, 기본값 Kp≈50 / Ki=0 / Kd=0에서 시작. 온도가 높으면 Kp를 조금 올리고, 출렁이면 내립니다.  
  - Interval: 기본 1.0초, 0.2초 이하로 낮추면 노이즈·부하가 커질 수 있음.  
  - `Start`로 제어 시작, `Monitor Only`는 읽기 전용, `Apply`로 실행 중 설정 반영, `Stop`으로 자동 모드 복귀.
- Debug/Status: HID Sensors, SMC Sensors, Privileges 탭에서 실시간 값과 권한 상태를 확인.
- 권한(별도 가이드가 gitignore로 제외되어 여기에 요약): 앱은 비특권으로 실행되며, 첫 제어 시 Authorization Services 비밀번호 프롬프트가 떠서 SMCHelper를 설치/실행합니다. 자동 설치가 실패하면 Privileges 탭에서 터미널 명령을 복사해 쉘에서 실행하거나 `sudo /Applications/SMCController.app/Contents/MacOS/SMCController`를 직접 실행하세요. Helper fallback은 꺼져 있으므로 데몬이 있어야 제어 가능합니다.

## 데몬 관리
- 수동 설치/재설치:
```bash
cd SMCHelper
sudo ./install_daemon.sh
```
- 정리 후 재테스트:
```bash
./cleanup_daemon.sh
./check_daemon.sh
```
- 데몬이 없거나 실패하면 팬 제어는 에러를 반환합니다(Helper fallback 비활성). 필요 시 터미널에서 직접 실행:
```bash
sudo /Applications/SMCController.app/Contents/MacOS/SMCController
```

## 추가 문서
- `AUTO_INSTALL_GUIDE.md` 자동 설치 흐름
- `DAEMON_USAGE.md`, `PRIVILEGE_SEPARATION.md` 권한/아키텍처 메모
- `TROUBLESHOOT_INSTALL.md`, `DAEMON_START_FIX.md`, `ZOMBIE_PROCESS_FIX.md` 문제 해결
- `XCODE_SETUP.md` 번들 포함 설정, `ROLLBACK_NOTE.md`·`REBUILD_REQUIRED.md` 등 회귀 시 참고
- 문서 주의: `.gitignore`가 `README.md`를 제외한 `*.md`를 무시합니다. 위 가이드가 클론에 없다면 원본에서 내려받거나 커밋 전에 `.gitignore`에 개별 예외를 추가하세요.
