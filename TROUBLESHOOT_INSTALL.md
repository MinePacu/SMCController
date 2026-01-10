# 자동 설치 무한 루프 문제 해결

## 문제 증상

"Install Helper" 버튼을 누르면 같은 다이얼로그가 계속 다시 나타남

## 원인

가장 흔한 원인들:

### 1. SMCHelper 폴더가 앱 번들에 없음 (가장 흔함)
- Xcode에서 SMCHelper 폴더를 추가하지 않았거나
- "Create groups" 방식으로 추가했거나 (잘못됨)
- "Create folder references" 방식으로 추가해야 함 (올바름)

### 2. install_daemon.sh가 실행 권한이 없음
- Build Phase에서 Run Script 추가 안 함
- 스크립트 실행 권한 없음

### 3. AppleScript 권한 거부
- 사용자가 비밀번호 입력 취소
- macOS 보안 설정에서 차단

## 진단 방법

### 1. 번들 구조 확인

```bash
./debug_bundle.sh
```

이 스크립트가 다음을 확인합니다:
- ✅ SMCHelper 폴더 존재 여부
- ✅ install_daemon.sh 파일 존재 여부
- ✅ install_daemon.sh 실행 권한
- ✅ 필요한 파일들 (main_daemon.c, plist 등)

### 2. 앱 콘솔 로그 확인

Xcode에서 실행 시 콘솔에서 다음을 찾으세요:

**성공하는 경우:**
```
[DaemonClient] 🔧 Attempting to install daemon from bundle...
[DaemonClient] ✅ SMCHelper directory exists at: ...
[DaemonClient] ✅ Found install script at: ...
[DaemonClient] ✅ Script is executable
[DaemonClient] 🔐 Requesting admin privileges...
[DaemonClient] ✅ Installation script completed
[DaemonClient] ✅ Daemon started successfully with root: OK: Helper daemon running (euid=0)
```

**실패하는 경우 - 스크립트 없음:**
```
[DaemonClient] ❌ Install script not found in bundle
[DaemonClient] Searched for: install_daemon.sh in SMCHelper/
[DaemonClient] ℹ️ Make sure SMCHelper folder is added to Xcode with 'Create folder references'
```

**실패하는 경우 - 권한 거부:**
```
[DaemonClient] ❌ Installation failed with error:
[DaemonClient]    Error code: -128
[DaemonClient]    Error message: User canceled
```

**실패하는 경우 - 스크립트 오류:**
```
[DaemonClient] ❌ Installation failed with error:
[DaemonClient]    Error code: ...
[DaemonClient]    Error message: ...
```

## 해결 방법

### 해결 1: SMCHelper 폴더 올바르게 추가

1. Xcode에서 SMCController 프로젝트 열기

2. 프로젝트 네비게이터에서 기존 SMCHelper 참조 제거 (있다면)

3. File → Add Files to "SMCController"

4. SMCHelper 폴더 선택

5. **중요**: 다음 옵션 확인:
   - ⚪ Create groups (이거 아님!)
   - 🔵 **Create folder references** ← 이걸 선택!
   - ☑️ Copy items if needed
   - Target: ☑️ SMCController

6. 추가된 폴더가 **파란색** 폴더 아이콘인지 확인
   - 파란색 = 올바름 (folder reference)
   - 노란색 = 잘못됨 (group)

### 해결 2: Run Script Phase 추가

1. 프로젝트 선택 → Targets → SMCController

2. Build Phases 탭

3. "+" 버튼 → New Run Script Phase

4. 스크립트 입력:
```bash
#!/bin/bash
# Make install script executable
SCRIPT_PATH="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources/SMCHelper/install_daemon.sh"
if [ -f "$SCRIPT_PATH" ]; then
    chmod +x "$SCRIPT_PATH"
    echo "✅ Made install_daemon.sh executable"
else
    echo "⚠️ install_daemon.sh not found at: $SCRIPT_PATH"
fi
```

5. 이 Phase를 "Copy Bundle Resources" **다음**으로 드래그

### 해결 3: Info.plist 권한 추가 (macOS 12+)

1. 프로젝트 선택 → Targets → SMCController → Info

2. Custom macOS Target Properties에서 "+" 버튼

3. 다음 키 추가:
   - Key: `NSAppleEventsUsageDescription`
   - Type: String
   - Value: `SMCController needs to run installation scripts to set up the fan control helper.`

### 해결 4: Clean Build

1. Product → Clean Build Folder (⌘⇧K)

2. Product → Build (⌘B)

3. 빌드 로그에서 "Made install_daemon.sh executable" 확인

4. Product → Run (⌘R)

## 수동 확인

빌드 후 번들 내용 확인:

```bash
# Xcode 빌드 결과 확인
APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/SMCController-*/Build/Products/Debug/SMCController.app"
ls -la "$APP_PATH"/Contents/Resources/SMCHelper/

# install_daemon.sh 실행 권한 확인
ls -l "$APP_PATH"/Contents/Resources/SMCHelper/install_daemon.sh
# 출력: -rwxr-xr-x ... install_daemon.sh (x가 있어야 함)
```

## 재시도 제한

이제 자동으로 최대 2번까지만 시도합니다:
- 1차 시도 실패 → "Install Helper" 다시 표시 (Attempt 2 of 2)
- 2차 시도 실패 → 최종 실패 메시지 표시 (수동 설치 안내)

콘솔 로그:
```
[PrivilegeHelper] Requesting daemon start (attempt 1/2)...
[PrivilegeHelper] ❌ Failed to start daemon (attempt 1/2)
[PrivilegeHelper] Requesting daemon start (attempt 2/2)...
[PrivilegeHelper] ❌ Failed to start daemon (attempt 2/2)
[PrivilegeHelper] ❌ Max install retries (2) reached
```

## 빠른 테스트

전체 플로우 테스트:

```bash
# 1. 기존 helper 제거
sudo rm -f /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
sudo rm -f /tmp/com.minepacu.SMCHelper.socket

# 2. 번들 구조 확인
./debug_bundle.sh

# 3. 앱 실행
# Xcode에서 Run (⌘R)

# 4. 팬 제어 시도
# "Install Helper" 버튼 클릭
# 비밀번호 입력

# 5. 결과 확인
./check_daemon.sh
```

## 여전히 안 되면

### 임시 해결: 수동 설치

```bash
cd /path/to/SMCController/SMCHelper
sudo ./install_daemon.sh
```

설치 후 앱 재시작하면 helper를 인식함.

### 버그 리포트

다음 정보와 함께 이슈 제출:

1. `debug_bundle.sh` 출력
2. Xcode 콘솔 로그 (전체)
3. macOS 버전
4. Xcode 버전
5. 어떤 단계에서 실패했는지

## 체크리스트

디버깅 시 확인 사항:

- [ ] SMCHelper 폴더가 파란색 폴더 아이콘인가?
- [ ] Build Phases → Copy Bundle Resources에 SMCHelper가 있는가?
- [ ] Run Script Phase가 추가되었고 올바른 위치에 있는가?
- [ ] `debug_bundle.sh` 실행 시 모두 ✅인가?
- [ ] Info.plist에 NSAppleEventsUsageDescription이 있는가?
- [ ] Clean Build 후 재빌드 했는가?
- [ ] 비밀번호를 실제로 입력했는가? (취소 안 함)
- [ ] 콘솔 로그에 어떤 에러가 나오는가?
