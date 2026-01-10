# 비밀번호 프롬프트 문제 해결

## 문제

"Install Helper" 버튼을 눌러도 비밀번호를 요구하지 않고 설치가 진행되지 않음.

## 원인

AppleScript의 `do shell script ... with administrator privileges`는:
- 앱이 코드 서명되지 않았거나
- 시스템 설정에 따라
- **비밀번호를 요청하지 않고 조용히 실패**할 수 있음

## 해결

`AuthorizationExecuteWithPrivileges`를 사용하도록 변경:
- **반드시** 비밀번호 프롬프트 표시
- 더 안정적인 권한 획득
- Daemon 시작과 동일한 방식 사용

## 변경 사항

### 1. DaemonClient.swift
- ✅ AppleScript 제거
- ✅ `executeScriptWithAuth()` 메서드 추가
- ✅ `AuthorizationExecuteWithPrivileges` 사용

### 2. install_daemon.sh
- ✅ 이미 root로 실행 중일 때 `sudo` 생략
- ✅ `id -u`로 권한 확인
- ✅ 조건부 `$SUDO` 변수 사용

### 3. install_daemon_bundle.sh (신규)
- ✅ 번들 환경에 최적화
- ✅ SMCBridge.c를 여러 위치에서 탐색
- ✅ 상세한 디버그 출력

## 테스트 방법

### 1. 기존 Helper 제거

```bash
sudo rm -f /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
sudo rm -f /tmp/com.minepacu.SMCHelper.socket
sudo pkill -9 com.minepacu.SMCHelper
```

### 2. 앱 실행 (Xcode 콘솔 확인)

```bash
# Clean build
Product → Clean Build Folder (⌘⇧K)
Product → Build (⌘B)
Product → Run (⌘R)
```

### 3. 팬 제어 시도

콘솔에서 다음이 보여야 함:

```
[DaemonClient] 🔧 Attempting to install daemon from bundle...
[DaemonClient] ✅ SMCHelper directory exists at: ...
[DaemonClient] ✅ Found bundle install script at: ...
[DaemonClient] 🔐 Requesting admin privileges via Authorization Services...
[DaemonClient] 📢 YOU SHOULD SEE A PASSWORD PROMPT NOW
```

**이 시점에서 비밀번호 입력 창이 나타나야 함!**

### 4. 비밀번호 입력 후

```
[DaemonClient] ✅ Authorization granted, executing install script...
[DaemonClient] 📝 Install script output:
[DaemonClient]    ℹ️  Running as root (euid=0)
[DaemonClient]    🔨 Building SMCHelper daemon...
[DaemonClient]    ✅ SMCHelper daemon built successfully
[DaemonClient]    📦 Installing helper daemon...
[DaemonClient]    ✅ Helper installed to /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
[DaemonClient]    ✅ Daemon started successfully
[DaemonClient] ✅ Installation script executed successfully
```

### 5. 확인

```bash
./check_daemon.sh
```

예상 출력:
```
✅ Daemon binary installed
✅ Daemon process is running
✅ Daemon socket exists
✅ Daemon responded: OK: Helper daemon running (euid=0)
✅ Daemon is running with root privileges
```

## 여전히 비밀번호를 요구하지 않는 경우

### 체크 1: 번들에 스크립트가 있는지 확인

```bash
./debug_bundle.sh
```

다음이 모두 ✅여야 함:
- SMCHelper directory exists
- install_daemon_bundle.sh (또는 install_daemon.sh) found
- Script is executable

### 체크 2: 콘솔 로그 확인

"📢 YOU SHOULD SEE A PASSWORD PROMPT NOW" 메시지가 보이는가?

- **보이지 않음**: 스크립트를 찾지 못함 → 번들 설정 확인
- **보이지만 프롬프트 없음**: Authorization Services 문제 → 아래 참조

### 체크 3: macOS 보안 설정

System Preferences → Security & Privacy → Privacy:
- "Accessibility" 확인
- "Automation" 확인
- 필요시 SMCController 추가

### 체크 4: 앱 코드 서명

개발 중에는 서명 없어도 작동해야 하지만, 문제가 있다면:

```bash
# 임시 서명
codesign --force --deep --sign - \
  ~/Library/Developer/Xcode/DerivedData/.../SMCController.app
```

## 번들 설정 재확인

### Xcode에서:

1. **SMCHelper 폴더**:
   - 파란색 폴더 아이콘 (folder reference)
   - 노란색이면 잘못됨 (group)

2. **Build Phases → Copy Bundle Resources**:
   - SMCHelper/ 전체 또는
   - install_daemon_bundle.sh 파일

3. **Run Script Phase** (Copy Bundle Resources 다음):
```bash
#!/bin/bash
RESOURCES="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources"
for script in install_daemon.sh install_daemon_bundle.sh; do
    SCRIPT_PATH="$RESOURCES/SMCHelper/$script"
    if [ -f "$SCRIPT_PATH" ]; then
        chmod +x "$SCRIPT_PATH"
        echo "✅ Made $script executable"
    fi
done
```

4. **SMCBridge.c 포함**:
   - SMCHelper/ 폴더에 복사하거나
   - Resources에 별도 추가

## 수동 테스트

번들 없이 직접 스크립트 실행:

```bash
cd /path/to/SMCController/SMCHelper
sudo ./install_daemon.sh
```

이게 작동하면 → 번들 설정 문제
이것도 안 되면 → 스크립트 자체 문제

## 권장 디버깅 순서

1. `./debug_bundle.sh` 실행 → 모두 ✅인지 확인
2. Xcode Clean Build → Build
3. 앱 실행, 콘솔에서 "📢 YOU SHOULD SEE" 메시지 확인
4. 비밀번호 프롬프트 확인
5. 설치 로그 확인
6. `./check_daemon.sh` 실행

## 로그 수집 (이슈 제출 시)

```bash
# 1. 번들 구조
./debug_bundle.sh > bundle_debug.txt

# 2. 앱 실행 로그
# Xcode 콘솔 전체 복사

# 3. Daemon 상태
./check_daemon.sh > daemon_status.txt

# 4. 시스템 로그
sudo log show --predicate 'process == "SMCHelper"' --last 5m > system_log.txt
```

이 4개 파일과 함께 이슈 제출.
