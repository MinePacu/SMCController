# Fan Control 사용 가이드

## 개요

Fan Control 페이지에서 온도-RPM 커브를 설정하고 Start 버튼을 누르면:
1. **온도 모니터링** - 설정한 센서에서 온도 읽기
2. **RPM 계산** - 커브/PID에 따라 목표 RPM 계산
3. **팬 제어** - Daemon을 통해 팬 속도 설정
4. **실시간 표시** - 그래프에 현재 온도/RPM 표시

## 사용 방법

### 1. 기본 설정

#### 센서 설정
- **Sensor Key**: 온도를 읽을 SMC 센서 키
  - Intel: `TC0P` (CPU Proximity)
  - Apple Silicon: `Tp09` (PMU Die 9) - 자동 감지됨

#### 팬 설정
- **Fan Index**: 제어할 팬 번호 (0부터 시작)
- **Min/Max RPM**: 하드웨어에서 자동으로 읽어옴
- **Refresh Fan Limits**: 팬 정보 다시 읽기

#### 제어 주기
- **Interval**: 온도 확인 및 RPM 업데이트 주기 (초)
- 권장: 1.0초 (너무 짧으면 불안정)

### 2. 커브 설정

#### 포인트 추가/제거
- **Add Point**: 커브에 포인트 추가 (최대 12개)
- **Remove Point**: 마지막 포인트 제거 (최소 2개)

#### 포인트 조정
- **그래프에서 드래그**: 직관적으로 조정
- **테이블에서 입력**: 정확한 값 입력
  - P1, P2, ... : 각 포인트
  - Temp °C: 온도
  - RPM: 팬 속도

#### 커브 동작
- 온도가 포인트 사이일 때: **선형 보간**
- 온도가 최소값 이하: 최소 RPM
- 온도가 최대값 이상: 최대 RPM

예시:
```
40°C → 1200 RPM
60°C → 2000 RPM
75°C → 3000 RPM
90°C → 4000 RPM

현재 온도 50°C → 1600 RPM (40-60 사이 선형 보간)
```

### 3. PID 제어 (선택사항)

#### Enable PID 체크
- 커브 기반 제어에 PID 조정 추가
- 더 정밀한 온도 제어

#### 파라미터
- **Target (°C)**: 목표 온도
- **Kp**: 비례 게인 (권장: 50)
- **Ki**: 적분 게인 (권장: 0)
- **Kd**: 미분 게인 (권장: 0)

#### 동작 방식
1. 커브에서 기본 RPM 계산
2. PID가 온도 오차(현재 - 목표) 계산
3. PID 조정값을 RPM에 추가
4. 최종 RPM = 커브 RPM + PID 조정

### 4. 실행

#### Start 버튼
1. Daemon이 설치되어 있는지 확인
2. 없으면 자동 설치 (비밀번호 1회 입력)
3. 팬 제어 루프 시작:
   - 온도 읽기
   - RPM 계산
   - 팬 속도 설정
   - 주기적 반복

#### Monitor Only 버튼
- 팬 제어 없이 온도만 모니터링
- 설정 테스트용

#### Apply 버튼
- 실행 중에 설정 변경 적용
- 커브, PID 파라미터 등

#### Stop 버튼
- 팬 제어 중지
- 자동 모드로 복귀

## 실시간 모니터링

### 그래프 표시
- **파란 선**: 설정한 온도-RPM 커브
- **빨간 수직선**: 현재 온도
- **초록 수평선**: 현재 적용 RPM

### Monitoring 섹션
- **CPU Avg**: CPU 평균 온도
- **CPU Hot**: CPU 최고 온도
- **GPU**: GPU 온도
- **Fan RPM**: 현재 팬 속도

### 상태 표시
- 🟢 **Running**: 팬 제어 실행 중
- ⏸️ **Stopped**: 팬 제어 중지
- 📊 **Monitoring**: 센서 모니터링 중

## 권장 설정

### 조용한 운영 (저소음)
```
40°C → 1200 RPM (최소)
60°C → 1800 RPM
80°C → 2500 RPM
90°C → 3500 RPM

PID: Off
Interval: 2.0초
```

### 균형 (기본)
```
40°C → 1200 RPM
60°C → 2000 RPM
75°C → 3000 RPM
90°C → 4500 RPM

PID: Off 또는 Kp=50
Interval: 1.0초
```

### 쿨링 우선 (성능)
```
35°C → 1500 RPM
50°C → 2500 RPM
65°C → 3500 RPM
80°C → 5000 RPM (최대)

PID: On, Target=60°C, Kp=100
Interval: 0.5초
```

### Apple Silicon M 시리즈
```
45°C → 1200 RPM
65°C → 2000 RPM
80°C → 3000 RPM
95°C → 4000 RPM

PID: Off (실험적)
Interval: 1.5초
Sensor: Tp09 (자동)
```

## 문제 해결

### 팬이 작동하지 않음
1. Daemon 설치 확인: `./check_daemon.sh`
2. 콘솔에서 에러 확인
3. Stop → Start 다시 시도

### 온도가 표시되지 않음
- Sensor Key 확인
- Intel: TC0P, TC0D 등
- Apple Silicon: Tp09, Tp0T 등
- Monitor Only로 테스트

### RPM이 설정대로 안 됨
- Apple Silicon은 실험적 지원
- macOS가 팬 제어를 재정의할 수 있음
- 실제 RPM 확인: Monitoring 섹션

### 그래프에 현재 상태 안 보임
- Start 버튼 누름 확인
- 온도 센서가 작동하는지 확인
- Monitor Only로 센서 테스트

## 주의 사항

⚠️ **Apple Silicon**: 팬 제어가 실험적 지원입니다. 사용 시 주의하세요.

⚠️ **온도 관리**: 너무 낮은 RPM 설정 시 과열 위험. 안전 마진 유지하세요.

⚠️ **하드웨어 한계**: Min/Max RPM은 하드웨어가 지원하는 범위입니다.

✅ **자동 복귀**: 앱 종료 시 자동으로 팬이 자동 모드로 돌아갑니다.

## 작동 원리

### 제어 루프
```
1. 온도 읽기 (Sensor Key)
   ↓
2. 커브에서 RPM 계산 (선형 보간)
   ↓
3. PID 조정 (옵션)
   ↓
4. RPM 제한 (Min/Max)
   ↓
5. Daemon → 팬 속도 설정
   ↓
6. 대기 (Interval)
   ↓
반복
```

### Daemon 사용
- 앱: 일반 권한
- Daemon: root 권한
- 통신: Unix 소켓
- 설치: 한 번만 (자동)

## 추가 기능

### Extra Sensor Keys
- 추가 센서 모니터링 (제어 X)
- 쉼표로 구분: `TC0E,TG0D,Tp0a`

### Refresh Fan Limits
- 팬 정보 다시 읽기
- 캐시 무효화
- 다른 팬으로 변경 시

### Monitor Only
- 팬 제어 없이 센서만 확인
- 설정 검증용
- 안전한 테스트
