# Xcode 프로젝트 설정 가이드

## SMCHelper 폴더를 앱 번들에 포함시키기

자동 설치 기능이 작동하려면 SMCHelper 폴더의 스크립트와 소스 파일들이 앱 번들에 포함되어야 합니다.

### 1. Xcode에서 SMCHelper 폴더 추가

1. Xcode에서 SMCController 프로젝트 열기
2. 프로젝트 네비게이터에서 프로젝트 루트 선택
3. File → Add Files to "SMCController" 선택
4. `SMCHelper` 폴더 선택
5. **중요**: 다음 옵션 선택:
   - ☑️ "Create folder references" (Create groups가 아님!)
   - ☑️ "Copy items if needed"
   - Target: ☑️ "SMCController" 체크

### 2. Build Phases 확인

1. 프로젝트 선택 → Targets → SMCController
2. "Build Phases" 탭 선택
3. "Copy Bundle Resources" 섹션 확인
4. 다음 파일들이 포함되어 있는지 확인:
   - `SMCHelper/install_daemon.sh`
   - `SMCHelper/main_daemon.c`
   - `SMCHelper/com.minepacu.SMCHelper.plist`

### 3. 스크립트 실행 권한 설정

Build Phase를 추가하여 스크립트 실행 권한 설정:

1. "Build Phases" 탭에서 "+" 버튼 클릭
2. "New Run Script Phase" 선택
3. 다음 스크립트 입력:

```bash
#!/bin/bash
# Make install script executable in bundle
if [ -f "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources/SMCHelper/install_daemon.sh" ]; then
    chmod +x "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources/SMCHelper/install_daemon.sh"
    echo "✅ Made install_daemon.sh executable"
fi
```

4. 이 Phase를 "Copy Bundle Resources" 다음으로 이동

### 4. 번들 포함 확인

빌드 후 확인:

```bash
# 앱 번들 내용 확인
ls -la ~/Library/Developer/Xcode/DerivedData/SMCController-*/Build/Products/Debug/SMCController.app/Contents/Resources/SMCHelper/

# 또는 빌드된 앱에서 직접 확인
ls -la /Applications/SMCController.app/Contents/Resources/SMCHelper/
```

다음 파일들이 있어야 함:
- `install_daemon.sh` (실행 권한 있음)
- `main_daemon.c`
- `com.minepacu.SMCHelper.plist`
- `SMCBridge.c` (상위 폴더에서 참조)

### 5. DaemonClient.swift 파일 추가

1. File → Add Files to "SMCController"
2. `SMCController/DaemonClient.swift` 선택
3. Target: ☑️ "SMCController" 체크
4. "Add" 클릭

### 6. 빌드 및 테스트

1. Product → Clean Build Folder (⌘⇧K)
2. Product → Build (⌘B)
3. 에러 없이 빌드 성공 확인
4. Product → Run (⌘R)
5. 팬 제어 시도 시 자동 설치 프롬프트 확인

## 문제 해결

### "Install script not found in bundle" 에러

번들에 스크립트가 없음:

1. Build Phases → Copy Bundle Resources에 SMCHelper 폴더가 있는지 확인
2. "Create folder references"로 추가했는지 확인 (파란 폴더 아이콘)
3. Clean Build Folder 후 재빌드

### 스크립트 실행 권한 없음

Run Script Phase가 실행되지 않음:

1. Build Phases에서 Run Script Phase가 Copy Bundle Resources 뒤에 있는지 확인
2. 스크립트에 `#!/bin/bash`가 있는지 확인
3. Clean Build Folder 후 재빌드

### AppleScript 권한 오류

macOS Monterey 이상에서 AppleScript 실행 권한 필요:

1. Info.plist에 다음 키 추가:
```xml
<key>NSAppleEventsUsageDescription</key>
<string>SMCController needs to run installation scripts to set up the fan control helper.</string>
```

2. System Preferences → Security & Privacy → Privacy → Automation에서 SMCController 허용

### 자동 설치가 실패하면

수동 설치 안내:

```bash
cd /path/to/SMCController/SMCHelper
sudo ./install_daemon.sh
```

## 배포 시 주의사항

### App Store 배포

App Store에 배포할 경우:
- Sandboxing과 충돌할 수 있음
- Helper를 별도 설치 패키지로 제공 권장
- 또는 XPC Service 사용 고려

### 직접 배포

.app 파일을 직접 배포할 경우:
- SMCHelper 폴더가 번들에 포함되어 있는지 확인
- 첫 실행 시 자동 설치 안내
- 사용자에게 관리자 권한 필요함을 명시

### 코드 서명

Helper에도 서명 필요:

```bash
codesign --force --sign "Developer ID Application: Your Name" /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
```

자동 설치 스크립트에 서명 단계 추가 고려.
