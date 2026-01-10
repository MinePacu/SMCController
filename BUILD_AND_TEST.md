# 빌드 및 테스트 가이드

## 빠른 시작

### 1. 바이너리 준비
```bash
cd SMCHelper
./prepare_bundle.sh
```

확인:
```bash
ls -la SMCHelper install_helper
# 두 파일 모두 존재하고 실행 가능(rwx)해야 함
```

### 2. Xcode에 파일 추가

**중요**: 개별 파일로 추가 (폴더 전체 X)

File → Add Files to "SMCController":
- `SMCHelper/SMCHelper` ✓
- `SMCHelper/install_helper` ✓
- `SMCHelper/com.minepacu.SMCHelper.plist` ✓

옵션:
- ☑️ Copy items if needed
- ⚪ Create groups (기본값)
- Target: ☑️ SMCController

### 3. Build Phases 확인

**Compile Sources**에서 제거:
- ❌ main.c
- ❌ main_daemon.c
- ❌ install_helper.c
- ❌ SMCBridge.c (SMCHelper 폴더의)

**Copy Bundle Resources**에 있어야 함:
- ✅ SMCHelper
- ✅ install_helper
- ✅ com.minepacu.SMCHelper.plist

### 4. 빌드
```bash
Product → Clean Build Folder (⌘⇧K)
Product → Build (⌘B)
```

### 5. 번들 확인
```bash
APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/SMCController-*/Build/Products/*/SMCController.app"
ls -la "$APP_PATH"/Contents/Resources/ | grep -E "SMC|install"
```

다음이 보여야 함:
```
-rwxr-xr-x  ... SMCHelper
-rwxr-xr-x  ... install_helper
-rw-r--r--  ... com.minepacu.SMCHelper.plist
```

### 6. 테스트

기존 helper 제거:
```bash
sudo rm -f /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
sudo rm -f /tmp/com.minepacu.SMCHelper.socket
```

앱 실행:
```bash
Product → Run (⌘R)
```

팬 제어 시도 → 비밀번호 입력 → 설치 완료!

### 7. 확인
```bash
./check_daemon.sh
```

모두 ✅여야 함.

## 콘솔 로그 확인

성공 시:
```
[DaemonClient] ✅ Found helper binary: .../SMCHelper
[DaemonClient] ✅ Found plist: .../com.minepacu.SMCHelper.plist
[DaemonClient] ✅ Found installer: .../install_helper
[DaemonClient] 📢 YOU SHOULD SEE A PASSWORD PROMPT NOW
[DaemonClient] 📝 Installer output:
[DaemonClient]    🔧 SMCHelper Installer
[DaemonClient]    ✅ Helper binary installed
[DaemonClient]    ✅ Daemon loaded
```

실패 시:
```
[DaemonClient] ❌ Required files not found in bundle
```
→ 번들에 파일이 없음, 2단계부터 다시

## 문제 해결

### duplicate symbols 에러
→ Compile Sources에서 .c 파일들 제거

### Required files not found
→ Copy Bundle Resources에 3개 파일 확인

### 비밀번호 프롬프트 안 나옴
→ 콘솔 로그 확인, "📢 YOU SHOULD SEE" 메시지 있는지

### 설치 실패
→ "Installer output" 섹션에서 정확한 에러 확인
