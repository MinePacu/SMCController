# SMCController 권한 가이드

## Stats 방식과의 차이점

**Stats가 사용하는 방식:**
- Privileged Helper Tool (LaunchDaemon)
- 복잡한 XPC 통신
- 코드 서명 및 notarization 필수
- 개발자 계정 필요

**우리의 접근 방식:**
- 간단한 sudo 실행
- 복잡한 설정 불필요
- 즉시 사용 가능

## 사용 방법

### 방법 1: 터미널에서 실행 (권장)

1. 앱 실행
2. "Privileges" 탭 클릭
3. "Copy Command & Show Instructions" 버튼 클릭
4. Terminal 열고 붙여넣기 (⌘V)
5. 비밀번호 입력
6. 완료!

### 방법 2: 수동 실행

```bash
sudo /Applications/SMCController.app/Contents/MacOS/SMCController
```

### 방법 3: Alias 만들기 (편의성)

`~/.zshrc` 또는 `~/.bash_profile`에 추가:

```bash
alias smccontroller='sudo /Applications/SMCController.app/Contents/MacOS/SMCController'
```

이후 터미널에서 `smccontroller` 명령으로 실행 가능

## 자동 시작 설정 (선택사항)

부팅 시 자동으로 실행하려면:

1. `/Library/LaunchDaemons/com.nohyunsoo.smccontroller.plist` 생성:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.nohyunsoo.smccontroller</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/SMCController.app/Contents/MacOS/SMCController</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
```

2. 권한 설정 및 로드:

```bash
sudo chown root:wheel /Library/LaunchDaemons/com.nohyunsoo.smccontroller.plist
sudo chmod 644 /Library/LaunchDaemons/com.nohyunsoo.smccontroller.plist
sudo launchctl load /Library/LaunchDaemons/com.nohyunsoo.smccontroller.plist
```

3. 제거하려면:

```bash
sudo launchctl unload /Library/LaunchDaemons/com.nohyunsoo.smccontroller.plist
sudo rm /Library/LaunchDaemons/com.nohyunsoo.smccontroller.plist
```

## 보안 고려사항

**Q: sudo로 실행해도 안전한가요?**

A: 네. SMCController는:
- 로컬 Mac에서만 실행
- 네트워크 연결 없음
- SMC 하드웨어 접근만 수행
- 시스템 파일 수정 없음

**Q: Stats보다 덜 안전한가요?**

A: 기술적으로는 동일합니다. Stats도 결국 root 권한으로 SMC에 접근합니다. 차이점은:
- Stats: Helper Tool이 항상 root로 실행 (백그라운드)
- 우리: 앱 전체가 root로 실행 (명시적)

둘 다 같은 수준의 하드웨어 접근 권한을 가집니다.

## 문제 해결

### "Operation not permitted" 오류

Full Disk Access 권한 필요:
1. System Settings > Privacy & Security > Full Disk Access
2. Terminal.app 추가
3. 다시 시도

### 비밀번호를 계속 물어봄

sudo timeout 연장:
```bash
sudo visudo
```

다음 줄 추가:
```
Defaults timestamp_timeout=60
```

(60분 동안 비밀번호 재요청 안 함)
