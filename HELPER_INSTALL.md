# Helper Tool 설치 가이드

## 자동 설치 (앱에서)

1. 앱 실행
2. **"Privileges"** 탭 클릭
3. **"Install Helper Tool"** 버튼 클릭
4. 비밀번호 입력
5. 완료!

## 수동 설치 (터미널)

```bash
cd /Users/nohyunsoo/Desktop/projects/SMCController/SMCHelper
./build.sh
```

비밀번호를 입력하면 Helper가 `/Library/PrivilegedHelperTools/com.nohyunsoo.SMCHelper`에 설치됩니다.

## 작동 방식

```
SMCController.app (일반 사용자 권한)
    ↓
SMCHelperProxy.swift (Swift wrapper)
    ↓
sudo /Library/PrivilegedHelperTools/com.nohyunsoo.SMCHelper set-fan 0 2000
    ↓
SMCHelper (C binary, root 권한)
    ↓
SMCBridge.c → IOKit → SMC Hardware
```

## 장점

- ✅ 메인 앱은 일반 권한으로 실행
- ✅ 메뉴 바 자동 숨기기 정상 작동
- ✅ 모든 macOS UI 기능 사용 가능
- ✅ 팬 제어만 Helper를 통해 root 권한으로 실행
- ✅ 보안상 더 안전 (최소 권한 원칙)

## 테스트

```bash
# Helper가 작동하는지 확인
sudo /Library/PrivilegedHelperTools/com.nohyunsoo.SMCHelper check

# 팬 속도 설정
sudo /Library/PrivilegedHelperTools/com.nohyunsoo.SMCHelper set-fan 0 2000

# 현재 RPM 확인
sudo /Library/PrivilegedHelperTools/com.nohyunsoo.SMCHelper get-rpm 0
```

## 제거

```bash
sudo rm /Library/PrivilegedHelperTools/com.nohyunsoo.SMCHelper
```
