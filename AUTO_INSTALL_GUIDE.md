# SMCController - 자동 Helper 설치 가이드

## 변경 사항

### 패키지 이름 변경
- **이전**: `com.nohyunsoo.SMCHelper`
- **현재**: `com.minepacu.SMCHelper`

### 자동 설치 기능 추가
앱을 처음 실행하면 Helper Daemon이 자동으로 설치됩니다.

## 사용 방법

### 1. 첫 실행 시

1. 앱을 실행합니다 (일반 권한으로, sudo 없이)
2. 팬 제어 기능 사용 시 자동으로 설치 프롬프트가 나타납니다
3. "Install Helper" 버튼을 클릭합니다
4. 관리자 비밀번호를 입력합니다
5. Helper Daemon이 자동으로 설치됩니다

### 2. 설치 확인

터미널에서 확인:
```bash
./check_daemon.sh
```

또는 수동으로:
```bash
# Helper 파일 확인
ls -la /Library/PrivilegedHelperTools/com.minepacu.SMCHelper

# Daemon 실행 확인
ps aux | grep com.minepacu.SMCHelper

# 소켓 확인
ls -la /tmp/com.minepacu.SMCHelper.socket

# 통신 테스트
echo "check" | nc -U /tmp/com.minepacu.SMCHelper.socket
```

### 3. 이후 사용

- 앱 재시작 후에도 비밀번호 입력 없이 바로 팬 제어 가능
- Helper Daemon이 백그라운드에서 계속 실행됨
- 앱은 일반 권한으로 실행되어 메뉴 바 정상 표시

## 동작 원리

### 자동 설치 플로우
```
앱 실행 (일반 권한)
    ↓
팬 제어 시도
    ↓
Helper 없음 감지
    ↓
자동 설치 시도 (번들 내 스크립트 사용)
    ↓
비밀번호 입력 (한 번만)
    ↓
Helper 설치 및 Daemon 시작
    ↓
팬 제어 성공
```

### 번들 구조
앱 번들 내에 다음 파일들이 포함됩니다:
```
SMCController.app/
  Contents/
    Resources/
      SMCHelper/
        install_daemon.sh    # 설치 스크립트
        main_daemon.c         # Daemon 소스
        SMCBridge.c          # SMC 브릿지
        com.minepacu.SMCHelper.plist  # LaunchDaemon 설정
```

### 설치 위치
- Helper Binary: `/Library/PrivilegedHelperTools/com.minepacu.SMCHelper`
- LaunchDaemon Plist: `/Library/LaunchDaemons/com.minepacu.SMCHelper.plist`
- Unix Socket: `/tmp/com.minepacu.SMCHelper.socket`

## 수동 설치 (개발 중)

자동 설치가 실패할 경우 수동으로 설치:

```bash
cd /path/to/SMCController/SMCHelper
sudo ./install_daemon.sh
```

## 제거

Helper를 제거하려면:

```bash
# Daemon 중지
sudo launchctl unload /Library/LaunchDaemons/com.minepacu.SMCHelper.plist

# 파일 삭제
sudo rm /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
sudo rm /Library/LaunchDaemons/com.minepacu.SMCHelper.plist
sudo rm /tmp/com.minepacu.SMCHelper.socket
```

## 기존 버전에서 마이그레이션

기존 `com.nohyunsoo.SMCHelper`를 사용했다면:

```bash
# 기존 Helper 제거
sudo launchctl unload /Library/LaunchDaemons/com.nohyunsoo.SMCHelper.plist
sudo rm /Library/PrivilegedHelperTools/com.nohyunsoo.SMCHelper
sudo rm /Library/LaunchDaemons/com.nohyunsoo.SMCHelper.plist
sudo rm /tmp/com.nohyunsoo.SMCHelper.socket

# 새 버전 앱 실행 시 자동으로 새 Helper 설치됨
```

## 문제 해결

### 자동 설치 실패
- "Install Helper" 버튼을 다시 클릭
- 또는 수동 설치 스크립트 실행

### Daemon이 응답하지 않음
```bash
sudo pkill -9 com.minepacu.SMCHelper
# 앱에서 팬 제어 다시 시도 → 자동 재시작
```

### 권한 문제
```bash
# Helper 권한 확인
ls -la /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
# 소유자: root:wheel, 권한: 755 여야 함

# 필요시 수정
sudo chown root:wheel /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
sudo chmod 755 /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
```

## 보안

- Helper는 root 권한으로 실행되지만, 제한된 기능만 제공:
  - SMC 팬 속도 설정
  - SMC 수동 모드 설정
  - 상태 확인
- Unix 소켓을 통한 통신으로 네트워크 노출 없음
- 소스 코드가 공개되어 있어 검증 가능

## 로그

설치 및 실행 로그는 앱의 콘솔 출력에서 확인:
```
[DaemonClient] Attempting auto-installation...
[DaemonClient] ✅ Daemon installed successfully
[DaemonClient] ✅ Daemon started successfully with root: OK: Helper daemon running (euid=0)
```
