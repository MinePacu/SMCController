# 패키지 이름 불일치 문제 수정

## 문제

plist 파일명은 `com.minepacu.SMCHelper.plist`로 변경했지만, **파일 내용**은 여전히 `com.nohyunsoo.SMCHelper`를 참조하고 있었습니다.

## 원인

plist 파일 내부의 3곳:
1. `<key>Label</key>` 값
2. `<key>ProgramArguments</key>` 경로
3. `<key>MachServices</key>` 키

## 수정 완료

다음 파일들의 내용 수정:
- ✅ `SMCHelper/com.minepacu.SMCHelper.plist`
- ✅ `SMCController/SMCHelper/com.minepacu.SMCHelper.plist`

모든 `com.nohyunsoo.SMCHelper` → `com.minepacu.SMCHelper` 변경

## 다음 단계

### 1. Clean Build

Xcode에서:
```bash
Product → Clean Build Folder (⌘⇧K)
Product → Build (⌘B)
```

### 2. 기존 helper 제거

```bash
# 이전 패키지 이름으로 설치된 것 제거
sudo launchctl unload /Library/LaunchDaemons/com.nohyunsoo.SMCHelper.plist 2>/dev/null
sudo rm -f /Library/PrivilegedHelperTools/com.nohyunsoo.SMCHelper
sudo rm -f /Library/LaunchDaemons/com.nohyunsoo.SMCHelper.plist
sudo rm -f /tmp/com.nohyunsoo.SMCHelper.socket

# 새 패키지 이름 것도 제거
sudo launchctl unload /Library/LaunchDaemons/com.minepacu.SMCHelper.plist 2>/dev/null
sudo rm -f /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
sudo rm -f /Library/LaunchDaemons/com.minepacu.SMCHelper.plist
sudo rm -f /tmp/com.minepacu.SMCHelper.socket
```

### 3. 앱 실행 및 설치

```bash
Product → Run (⌘R)
```

팬 제어 시도 → 비밀번호 입력 → 설치

### 4. 확인

```bash
./check_daemon.sh
```

예상 출력:
```
✅ Daemon binary installed at /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
✅ Daemon process is running
✅ Daemon socket exists at /tmp/com.minepacu.SMCHelper.socket
✅ Daemon responded: OK: Helper daemon running (euid=0)
✅ Daemon is running with root privileges
```

## 검증

올바른 패키지 이름 사용 확인:

```bash
# LaunchDaemon 확인
sudo launchctl list | grep SMC

# 출력 예상: com.minepacu.SMCHelper

# plist 내용 확인
cat /Library/LaunchDaemons/com.minepacu.SMCHelper.plist | grep "com\."

# 모두 com.minepacu.SMCHelper여야 함
```

## 완료!

이제 모든 참조가 `com.minepacu.SMCHelper`로 통일되었습니다.
