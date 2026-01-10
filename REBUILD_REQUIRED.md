# 바이너리 재빌드 완료

## 문제

오래된 `SMCHelper` 바이너리가 여전히 `com.nohyunsoo.SMCHelper.socket`을 사용하고 있었습니다.

소스 코드는 수정되었지만, **컴파일된 바이너리는 업데이트되지 않았습니다**.

## 해결

### 1. 바이너리 재빌드 ✅

```bash
cd SMCHelper
rm -f SMCHelper install_helper
./prepare_bundle.sh
```

새 바이너리 확인:
```bash
strings SMCHelper | grep "com\."
# 출력: /tmp/com.minepacu.SMCHelper.socket ✓
```

### 2. Xcode 프로젝트 파일 업데이트 ✅

```bash
cp -f SMCHelper/SMCHelper SMCController/SMCHelper/SMCHelper
cp -f SMCHelper/install_helper SMCController/SMCHelper/install_helper
```

## 다음 단계

### 1. Xcode Clean Build

**중요**: 새 바이너리가 번들에 포함되도록 Clean Build 필수!

```bash
Product → Clean Build Folder (⌘⇧K)
Product → Build (⌘B)
```

### 2. 기존 설치 완전 제거

```bash
# 이전 패키지 제거
sudo launchctl unload /Library/LaunchDaemons/com.nohyunsoo.SMCHelper.plist 2>/dev/null
sudo rm -f /Library/PrivilegedHelperTools/com.nohyunsoo.SMCHelper
sudo rm -f /Library/LaunchDaemons/com.nohyunsoo.SMCHelper.plist
sudo rm -f /tmp/com.nohyunsoo.SMCHelper.socket

# 새 패키지 제거
sudo launchctl unload /Library/LaunchDaemons/com.minepacu.SMCHelper.plist 2>/dev/null
sudo rm -f /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
sudo rm -f /Library/LaunchDaemons/com.minepacu.SMCHelper.plist
sudo rm -f /tmp/com.minepacu.SMCHelper.socket
```

### 3. 앱 실행 및 테스트

```bash
Product → Run (⌘R)
```

팬 제어 시도 → 비밀번호 입력

### 4. 성공 로그 확인

```
[DaemonClient] ✅ Found helper binary
[DaemonClient] ✅ Found plist
[DaemonClient] ✅ Found installer
[DaemonClient] 📢 YOU SHOULD SEE A PASSWORD PROMPT NOW
[DaemonClient] 📝 Installer output:
[DaemonClient]    🔧 SMCHelper Installer
[DaemonClient]    ✅ Helper binary installed
[DaemonClient]    ✅ Daemon loaded
[DaemonClient] ✅ Installer executed successfully
[DaemonClient] ⏳ Waiting for daemon to start...
Daemon started, listening on /tmp/com.minepacu.SMCHelper.socket ← 올바른 경로!
[DaemonClient] ✅ Daemon started successfully with root: OK: Helper daemon running (euid=0)
```

### 5. 최종 확인

```bash
./check_daemon.sh
```

예상 출력:
```
✅ Daemon binary installed at /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
✅ Daemon process is running
✅ Daemon socket exists at /tmp/com.minepacu.SMCHelper.socket ← 새 경로!
✅ Daemon responded: OK: Helper daemon running (euid=0)
✅ Daemon is running with root privileges
✅ App is running as user: username (correct)
```

## 중요 사항

### 소스 코드 변경 시 항상:

1. **바이너리 재빌드**:
```bash
cd SMCHelper
./prepare_bundle.sh
```

2. **Xcode 프로젝트 파일 업데이트** (Xcode에 바이너리를 직접 추가한 경우):
```bash
cp -f SMCHelper/SMCHelper SMCController/SMCHelper/SMCHelper
cp -f SMCHelper/install_helper SMCController/SMCHelper/install_helper
```

3. **Clean Build**:
```bash
Product → Clean Build Folder (⌘⇧K)
```

### 확인 방법

컴파일된 바이너리의 내용 확인:
```bash
strings SMCHelper/SMCHelper | grep socket
# 올바른 소켓 경로가 보여야 함
```

## 완료!

이제 모든 것이 `com.minepacu.SMCHelper`로 통일되었습니다:
- ✅ 소스 코드
- ✅ plist 파일 (파일명과 내용)
- ✅ 컴파일된 바이너리
- ✅ DaemonClient.swift
