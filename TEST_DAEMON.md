# Daemon 테스트 가이드

## 문제 해결 내역

### 원인
1. `main_daemon.c`에서 `chmod` 함수 사용 시 `<sys/stat.h>` 헤더 누락
2. 앱에서 Daemon과 통신하는 로직이 없어서 Daemon 시작 후 멈춤
3. **중요**: 앱이 sudo로 실행되면 daemon 대신 직접 SMC 접근 (메뉴 바 숨김)
4. Daemon이 root 권한 없이 실행될 수 있는 문제

### 해결
1. `main_daemon.c`에 `<sys/stat.h>` 헤더 추가
2. `DaemonClient.swift` 생성 - Unix 소켓으로 Daemon 통신
3. `SMC.swift` 수정 - Daemon을 최우선으로 사용
4. **`PrivilegeHelper.swift` 수정** - 앱 재시작 대신 daemon 시작
5. **Daemon 권한 검증** - euid=0 확인 및 자동 재시작

## 핵심 변경 사항

### 이전 동작 (문제)
```
앱 시작 → 권한 없음 → 암호 입력 → 앱을 sudo로 재시작 → 메뉴 바 숨김
```

### 현재 동작 (해결)
```
앱 시작 (일반 권한) → 팬 제어 필요 → Daemon 시작 (암호 1회) → Daemon이 root로 동작
→ 앱은 일반 권한 유지 → 메뉴 바 정상
```

## 테스트 순서

### 1. 기존 프로세스 정리

```bash
# 앱이 sudo로 실행 중이면 종료
sudo pkill -9 SMCController

# 기존 daemon 종료
sudo pkill -9 com.nohyunsoo.SMCHelper

# 소켓 파일 삭제
sudo rm -f /tmp/com.nohyunsoo.SMCHelper.socket
```

### 2. Daemon 빌드 및 설치

```bash
cd /Users/nohyunsoo/Desktop/projects/SMCController/SMCHelper
sudo ./install_daemon.sh
```

예상 출력:
```
🔨 Building SMCHelper daemon...
✅ Build successful
📦 Installing daemon...
✅ Daemon installed successfully
```

### 3. Xcode에서 파일 추가 및 빌드

Xcode에서 프로젝트를 열고:
1. `DaemonClient.swift` 파일을 프로젝트에 추가
2. Target을 "SMCController"로 선택
3. 빌드 (⌘B)

### 4. 앱 실행 및 테스트 (일반 권한으로!)

**중요**: Xcode에서 Run하거나 Finder에서 더블클릭으로 실행 (sudo 사용 금지)

1. 앱 실행
2. 팬 제어 시도
3. 비밀번호 요청 → Daemon 시작
4. **메뉴 바가 숨겨지지 않는지 확인!**

콘솔 로그에서 확인:
```
[PrivilegeHelper] Checking daemon availability...
[DaemonClient] Checking if daemon is running...
[DaemonClient] Daemon not running, attempting to start...
[DaemonClient] ✅ Daemon started successfully with root: OK: Helper daemon running (euid=0)
[Swift SMC] Setting fan 0 target RPM to 2000...
[DaemonClient] OK: Set fan 0 to 2000 RPM
[Swift SMC] ✅ Set fan 0 target RPM to 2000 via daemon
```

### 5. Daemon 상태 확인

```bash
# 편리한 체크 스크립트 사용
./check_daemon.sh
```

또는 수동으로:

```bash
# Daemon 프로세스 확인
ps aux | grep SMCHelper | grep -v grep

# 앱이 일반 권한으로 실행 중인지 확인
ps aux | grep SMCController.app | grep -v grep

# 소켓 확인
ls -la /tmp/com.nohyunsoo.SMCHelper.socket

# 수동 테스트
echo "check" | nc -U /tmp/com.nohyunsoo.SMCHelper.socket
```

**올바른 상태**:
- Daemon 프로세스: `root` 사용자로 실행
- 앱 프로세스: 일반 사용자로 실행
- 메뉴 바: 정상 표시

### 6. 재시작 후 테스트

앱을 종료하고 다시 실행:
- **비밀번호 없이** 바로 팬 제어 가능 (Daemon이 계속 실행 중)

## 문제 해결

### 메뉴 바가 여전히 숨겨지는 경우

```bash
# 앱이 sudo로 실행 중인지 확인
ps aux | grep SMCController.app | grep -v grep

# root로 실행 중이면 종료
sudo pkill -9 SMCController

# 일반 권한으로 다시 실행 (Xcode Run 또는 Finder에서 더블클릭)
```

### "Daemon not responding" 오류

```bash
sudo pkill -9 com.nohyunsoo.SMCHelper
# 앱에서 다시 팬 제어 시도 → 자동 재시작
```

### "Permission denied" 오류

```bash
# Daemon 재설치
cd /Users/nohyunsoo/Desktop/projects/SMCController/SMCHelper
sudo ./install_daemon.sh
```

### Daemon이 root가 아닌 권한으로 실행되는 경우

앱이 자동으로 감지하고 재시작하지만, 수동으로:

```bash
sudo pkill -9 com.nohyunsoo.SMCHelper
# 앱에서 다시 팬 제어 시도
```

## 변경된 파일 목록

1. `SMCHelper/main_daemon.c` - `<sys/stat.h>` 추가
2. `SMCController/DaemonClient.swift` - **새 파일** (daemon 권한 검증 추가)
3. `SMCController/SMC.swift` - Daemon 우선 사용
4. `SMCController/PrivilegeHelper.swift` - **중요 변경**: 앱 재시작 → daemon 시작
5. `check_daemon.sh` - **새 파일** (상태 확인 스크립트)
6. `DAEMON_USAGE.md` - 사용 가이드
7. `TEST_DAEMON.md` - 테스트 가이드

## 우선순위 (변경 없음)

```
DaemonClient (euid=0 검증, 자동 재시작)
    ↓ 실패
SMCHelperProxy (매번 비밀번호)
    ↓ 실패
Direct SMC (sudo 필요, 권장하지 않음)
```
