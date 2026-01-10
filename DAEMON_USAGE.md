# Daemon 기반 팬 제어 사용 가이드

## 개요

SMCController는 팬 속도를 제어하기 위해 권한이 필요합니다. 이를 위해 3가지 방법을 우선순위에 따라 시도합니다:

1. **Daemon 방식** (최우선, 권장) - 한 번 설치 후 비밀번호 없이 사용
2. **Helper Tool 방식** (차선) - 매번 비밀번호 필요
3. **Sudo 방식** (마지막) - 터미널에서 sudo로 앱 실행

## 1. Daemon 설치 및 사용 (권장)

### 설치 방법

터미널에서 다음 명령어를 실행하세요:

```bash
cd /Users/nohyunsoo/Desktop/projects/SMCController/SMCHelper
sudo ./install_daemon.sh
```

비밀번호를 한 번 입력하면 설치가 완료됩니다.

### 동작 방식

- Daemon이 `/Library/PrivilegedHelperTools/com.nohyunsoo.SMCHelper`에 설치됨
- 앱에서 팬 제어가 필요할 때 자동으로 Daemon 시작 (한 번만 비밀번호 입력)
- 이후부터는 비밀번호 없이 팬 제어 가능
- Unix 소켓 (`/tmp/com.nohyunsoo.SMCHelper.socket`)을 통해 통신

### 장점

- ✅ 한 번 설치 후 비밀번호 재입력 불필요
- ✅ 빠른 응답 속도
- ✅ 앱 재시작 후에도 계속 사용 가능

### 확인 방법

```bash
# Daemon 설치 확인
ls -la /Library/PrivilegedHelperTools/com.nohyunsoo.SMCHelper

# Daemon 실행 확인
ls -la /tmp/com.nohyunsoo.SMCHelper.socket
```

## 2. Helper Tool 방식 (차선)

Daemon이 없을 때 자동으로 Helper Tool을 시도합니다. 매번 비밀번호가 필요합니다.

## 3. Sudo 방식 (마지막 수단)

Daemon과 Helper Tool이 모두 실패하면, 직접 SMC에 접근합니다 (sudo로 앱 실행 필요).

```bash
sudo /Applications/SMCController.app/Contents/MacOS/SMCController
```

## 우선순위

코드는 다음 순서로 시도합니다:

```
DaemonClient (비밀번호 불필요)
    ↓ 실패
SMCHelperProxy (매번 비밀번호)
    ↓ 실패
Direct SMC (sudo 필요)
```

## 문제 해결

### Daemon이 응답하지 않을 때

```bash
# 실행 중인 daemon 확인
ps aux | grep SMCHelper

# 강제 종료 후 재시작
sudo pkill -9 com.nohyunsoo.SMCHelper
```

앱에서 팬 제어를 다시 시도하면 자동으로 재시작됩니다.

### Daemon 제거

```bash
sudo rm /Library/PrivilegedHelperTools/com.nohyunsoo.SMCHelper
```

## 로그 확인

앱의 콘솔 출력에서 다음을 확인할 수 있습니다:

- `[DaemonClient] ✅ Daemon started successfully` - Daemon 정상 동작
- `[Swift SMC] ✅ Set fan X target RPM to Y via daemon` - Daemon으로 팬 제어 성공
- `[DaemonClient] ❌ Daemon not available` - Daemon 사용 불가, 다른 방법 시도

## 코드 구조

- `DaemonClient.swift` - Unix 소켓을 통한 Daemon 통신 클라이언트
- `SMC.swift` - 3가지 방법을 우선순위에 따라 시도
- `main_daemon.c` - Daemon 서버 (root 권한으로 실행)
- `install_daemon.sh` - Daemon 빌드 및 설치 스크립트
