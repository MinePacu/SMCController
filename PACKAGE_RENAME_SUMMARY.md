# 패키지 이름 변경 및 자동 설치 요약

## 변경 사항

### 1. 패키지 이름 변경
- `com.nohyunsoo.SMCHelper` → `com.minepacu.SMCHelper`

### 2. 자동 설치 기능 추가
- 앱 첫 실행 시 Helper Daemon 자동 설치
- 사용자는 "Install Helper" 버튼 클릭 → 비밀번호 입력만 하면 됨

## 변경된 파일

### 소스 코드
1. ✅ `SMCHelper/main_daemon.c` - 소켓 경로 변경
2. ✅ `SMCHelper/build.sh` - 설치 경로 변경
3. ✅ `SMCHelper/install_daemon.sh` - 패키지 이름 변경
4. ✅ `SMCHelper/com.nohyunsoo.SMCHelper.plist` → `com.minepacu.SMCHelper.plist` 파일명 변경
5. ✅ `SMCController/DaemonClient.swift` - 경로 변경 + 자동 설치 로직 추가
6. ✅ `SMCController/SMCHelperProxy.swift` - 경로 변경
7. ✅ `SMCController/PrivilegeHelper.swift` - 자동 설치 지원 메시지 개선

### 문서
8. ✅ `check_daemon.sh` - 경로 변경
9. ✅ `AUTO_INSTALL_GUIDE.md` - 새 가이드 (자동 설치 설명)
10. ✅ `XCODE_SETUP.md` - 새 가이드 (번들 설정 방법)
11. ✅ `PACKAGE_RENAME_SUMMARY.md` - 이 파일

## 빌드 전 필수 작업

### Xcode 프로젝트 설정

1. **DaemonClient.swift 추가**
   - File → Add Files to "SMCController"
   - `SMCController/DaemonClient.swift` 선택
   - Target: SMCController 체크

2. **SMCHelper 폴더를 번들에 포함**
   - File → Add Files to "SMCController"
   - `SMCHelper` 폴더 선택
   - "Create folder references" 선택 (중요!)
   - "Copy items if needed" 체크
   - Target: SMCController 체크

3. **스크립트 실행 권한 설정**
   - Build Phases → "+" → New Run Script Phase
   - 스크립트 입력:
   ```bash
   #!/bin/bash
   if [ -f "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources/SMCHelper/install_daemon.sh" ]; then
       chmod +x "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources/SMCHelper/install_daemon.sh"
   fi
   ```
   - 이 Phase를 "Copy Bundle Resources" 뒤로 이동

4. **Info.plist 권한 추가** (선택사항, macOS 12+에서 필요할 수 있음)
   ```xml
   <key>NSAppleEventsUsageDescription</key>
   <string>SMCController needs to run installation scripts to set up the fan control helper.</string>
   ```

자세한 내용은 `XCODE_SETUP.md` 참조.

## 테스트 방법

### 1. 기존 Helper 제거 (있다면)

```bash
sudo launchctl unload /Library/LaunchDaemons/com.nohyunsoo.SMCHelper.plist 2>/dev/null
sudo rm -f /Library/PrivilegedHelperTools/com.nohyunsoo.SMCHelper
sudo rm -f /Library/LaunchDaemons/com.nohyunsoo.SMCHelper.plist
sudo rm -f /tmp/com.nohyunsoo.SMCHelper.socket
```

### 2. 앱 빌드 및 실행

```bash
# Clean build
Product → Clean Build Folder (⌘⇧K)

# Build
Product → Build (⌘B)

# Run (일반 권한으로!)
Product → Run (⌘R)
```

### 3. 자동 설치 확인

1. 앱 실행
2. 팬 제어 시도
3. 자동으로 설치 다이얼로그 표시
4. "Install Helper" 클릭
5. 비밀번호 입력
6. 설치 완료 확인

콘솔 로그:
```
[DaemonClient] ❌ Daemon not installed at /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
[DaemonClient] Attempting auto-installation...
[DaemonClient] Found install script at: /path/to/SMCController.app/Contents/Resources/SMCHelper/install_daemon.sh
[DaemonClient] ✅ Installation completed: success
[DaemonClient] ✅ Daemon started successfully with root: OK: Helper daemon running (euid=0)
```

### 4. 상태 확인

```bash
./check_daemon.sh
```

예상 출력:
```
✅ Daemon binary installed at /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
✅ Daemon process is running
✅ Daemon socket exists
✅ Daemon responded: OK: Helper daemon running (euid=0)
✅ Daemon is running with root privileges
✅ App is running as user: username (correct)
```

## 사용자 경험

### 이전 (수동 설치)
1. 앱 실행
2. "Daemon 없음" 경고
3. 터미널 열기
4. 복잡한 명령어 입력
5. 설치 완료

### 현재 (자동 설치)
1. 앱 실행
2. "Install Helper" 버튼 클릭
3. 비밀번호 입력
4. 완료! ✅

## 문제 해결

### 자동 설치 실패: "Install script not found in bundle"

번들에 SMCHelper 폴더가 없음:
- Xcode에서 SMCHelper 폴더를 "Create folder references"로 추가했는지 확인
- Build Phases → Copy Bundle Resources에 포함되어 있는지 확인

### 자동 설치 실패: "Permission denied"

AppleScript 실행 권한 문제:
- System Preferences → Security & Privacy → Privacy → Automation 확인
- Info.plist에 NSAppleEventsUsageDescription 추가

### 수동 설치로 대체

자동 설치가 계속 실패하면:
```bash
cd /path/to/SMCController/SMCHelper
sudo ./install_daemon.sh
```

## 마이그레이션 체크리스트

- [x] 소스 코드 경로 업데이트
- [x] plist 파일명 변경
- [x] 자동 설치 로직 구현
- [x] 사용자 메시지 개선
- [x] 문서 업데이트
- [ ] Xcode 프로젝트에 DaemonClient.swift 추가
- [ ] Xcode 프로젝트에 SMCHelper 폴더 번들 포함
- [ ] Build Phase 스크립트 추가
- [ ] 빌드 및 테스트
- [ ] 자동 설치 동작 확인

## 참고 문서

- `AUTO_INSTALL_GUIDE.md` - 자동 설치 기능 상세 설명
- `XCODE_SETUP.md` - Xcode 프로젝트 설정 방법
- `TEST_DAEMON.md` - 전체 테스트 가이드
- `DAEMON_USAGE.md` - Daemon 사용법
