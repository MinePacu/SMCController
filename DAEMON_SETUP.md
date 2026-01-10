# Helper Daemon 설치 및 사용 가이드

## 개요

Helper Tool을 **LaunchDaemon**으로 실행하여:
- 메인 앱은 일반 사용자 권한으로 실행
- Helper만 root 권한으로 백그라운드 실행
- Unix socket으로 통신

## 설치 방법

```bash
cd /Users/nohyunsoo/Desktop/projects/SMCController/SMCHelper
./install_daemon.sh
```

비밀번호를 입력하면 다음 작업을 수행합니다:
1. Helper 바이너리 빌드
2. `/Library/PrivilegedHelperTools/com.nohyunsoo.SMCHelper` 설치
3. LaunchDaemon plist 설치
4. Daemon 시작

## 확인

```bash
# Daemon이 실행 중인지 확인
sudo launchctl list | grep SMCHelper

# Socket이 생성되었는지 확인
ls -la /tmp/com.nohyunsoo.SMCHelper.socket

# 로그 확인
cat /tmp/com.nohyunsoo.SMCHelper.log

# 테스트
echo "check" | nc -U /tmp/com.nohyunsoo.SMCHelper.socket
```

## 앱 수정 필요

`SMCHelperProxy.swift`의 `runHelper()` 함수를 Unix socket 통신 방식으로 변경해야 합니다.

현재 파일들이 잠겨있어 직접 수정이 필요합니다:

1. Xcode에서 `SMCHelperProxy.swift` 열기
2. `runHelper()` 함수를 다음과 같이 수정:

```swift
private func runHelper(args: [String]) throws -> String {
    // Connect to daemon via Unix socket
    let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard socketFD >= 0 else {
        throw NSError(domain: "SMCHelper", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
    }
    
    defer { close(socketFD) }
    
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let socketPath = "/tmp/com.nohyunsoo.SMCHelper.socket"
    _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
        socketPath.withCString { pathPtr in
            strncpy(ptr, pathPtr, MemoryLayout.size(ofValue: addr.sun_path))
        }
    }
    
    // Connect
    let connectResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            Darwin.connect(socketFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    
    guard connectResult >= 0 else {
        throw NSError(domain: "SMCHelper", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to connect to helper daemon"])
    }
    
    // Send command
    let command = args.joined(separator: " ") + "\n"
    guard let data = command.data(using: .utf8) else {
        throw NSError(domain: "SMCHelper", code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to encode command"])
    }
    
    _ = data.withUnsafeBytes { ptr in
        write(socketFD, ptr.baseAddress, data.count)
    }
    
    // Read response
    var buffer = [UInt8](repeating: 0, count: 1024)
    let readResult = read(socketFD, &buffer, buffer.count)
    
    guard readResult > 0 else {
        throw NSError(domain: "SMCHelper", code: -5,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to read response"])
    }
    
    guard let response = String(bytes: buffer[0..<readResult], encoding: .utf8) else {
        throw NSError(domain: "SMCHelper", code: -6,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to decode response"])
    }
    
    if response.hasPrefix("ERROR:") {
        throw NSError(domain: "SMCHelper", code: -7,
                    userInfo: [NSLocalizedDescriptionKey: response])
    }
    
    return response.trimmingCharacters(in: .whitespacesAndNewlines)
}
```

## 제거

```bash
sudo launchctl unload /Library/LaunchDaemons/com.nohyunsoo.SMCHelper.plist
sudo rm /Library/LaunchDaemons/com.nohyunsoo.SMCHelper.plist
sudo rm /Library/PrivilegedHelperTools/com.nohyunsoo.SMCHelper
sudo rm /tmp/com.nohyunsoo.SMCHelper.socket
```

## 이점

- ✅ 메인 앱은 일반 권한으로 실행
- ✅ 메뉴 바 자동 숨기기 정상 작동
- ✅ Helper만 root로 백그라운드 실행
- ✅ 비밀번호 요청 없음 (이미 설치됨)
- ✅ 부팅 시 자동 시작
