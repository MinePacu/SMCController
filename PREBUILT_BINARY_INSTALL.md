# 미리 빌드된 바이너리 설치 방식

## 핵심 아이디어

Shell script 대신 **미리 빌드된 C 프로그램**으로 설치하여 안정성 확보.

## 준비

### 1단계: 바이너리 빌드

```bash
cd SMCHelper
./prepare_bundle.sh
```

생성물:
- `SMCHelper` - Daemon 바이너리 (~40KB)
- `install_helper` - 설치 도구 (~20KB)
- `com.minepacu.SMCHelper.plist` (이미 존재)

### 2단계: Xcode 프로젝트에 추가

1. Xcode에서 File → Add Files to "SMCController"
2. 다음 파일 선택:
   - `SMCHelper/SMCHelper`
   - `SMCHelper/install_helper`  
   - `SMCHelper/com.minepacu.SMCHelper.plist`
3. 옵션:
   - ☑️ Copy items if needed
   - ☑️ Create folder references (파란 폴더)
   - Target: ☑️ SMCController

### 3단계: 확인

Build Phases → Copy Bundle Resources에서 확인:
- SMCHelper/SMCHelper
- SMCHelper/install_helper
- SMCHelper/com.minepacu.SMCHelper.plist

## 빌드 및 테스트

```bash
# Xcode에서
Product → Clean Build Folder (⌘⇧K)
Product → Build (⌘B)
Product → Run (⌘R)
```

팬 제어 시도 → **비밀번호 입력** → 설치 완료

## 로그 확인

성공 시:
```
[DaemonClient] ✅ Found helper binary
[DaemonClient] ✅ Found plist
[DaemonClient] ✅ Found installer
[DaemonClient] 📢 YOU SHOULD SEE A PASSWORD PROMPT NOW
[DaemonClient] 📝 Installer output:
[DaemonClient]    🔧 SMCHelper Installer
[DaemonClient]    ✅ Helper binary installed
[DaemonClient]    ✅ LaunchDaemon plist installed
[DaemonClient]    ✅ Daemon loaded
[DaemonClient]    ✅ Installation complete!
```

## 장점

1. ✅ **확실한 비밀번호 프롬프트** - C 프로그램은 항상 작동
2. ✅ **빠른 설치** - 빌드 과정 없음, 단순 복사
3. ✅ **안정적** - 환경 변수 문제 없음
4. ✅ **디버깅 쉬움** - 명확한 에러 메시지

## 문제 해결

### 파일 없음 에러

```bash
cd SMCHelper
ls -la SMCHelper install_helper
```

없으면 `./prepare_bundle.sh` 실행

### 비밀번호 프롬프트 안 나옴

- 콘솔에서 "📢 YOU SHOULD SEE" 메시지 확인
- 번들에 파일이 포함되었는지 확인

### 설치 실패

콘솔의 "Installer output" 섹션에서 정확한 오류 확인

## 확인

```bash
./check_daemon.sh
```

모두 ✅여야 함!
