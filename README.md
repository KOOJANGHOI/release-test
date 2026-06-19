# release-test

Release 자동화 스크립트 모음

## 스크립트 목록

### 1. create-release-server.sh
Server용 Release Branch 생성 및 Ready-To-Merge PR 병합 스크립트

**특징:**
- 모든 ready-to-merge 레이블이 붙은 PR을 처리
- 기존 release 브랜치가 있으면 재사용 (충돌 해결 후 재실행 가능)
- Squash 병합 방식

**사용법:**
```bash
./create-release-server.sh              # 실제 운영 실행
./create-release-server.sh --dry-run    # 모의 실행 (원격 반영 없음)
```

### 2. create-release-desktop.sh
Desktop용 Release Branch 생성 및 Desktop 브랜치 병합 스크립트

**특징:**
- `desktop/`으로 시작하는 브랜치만 필터링하여 병합
  - 예: `desktop/20260619/alice-feature`
- 기존 release 브랜치가 있으면 재사용
- Squash 병합 방식

**사용법:**
```bash
./create-release-desktop.sh              # 실제 운영 실행
./create-release-desktop.sh --dry-run    # 모의 실행 (원격 반영 없음)
```

### 3. create-test-prs.sh
테스트용 ready-to-merge PR 생성 스크립트

**사용법:**
```bash
./create-test-prs.sh       # 기본 3개 생성
./create-test-prs.sh 5     # 5개의 PR 생성
```

### 4. create-test-desktop-prs.sh
테스트용 Desktop ready-to-merge PR 생성 스크립트

**사용법:**
```bash
./create-test-desktop-prs.sh       # 기본 3개 생성  
./create-test-desktop-prs.sh 5     # 5개의 Desktop PR 생성
```

### 5. cleanup-test-prs.sh
테스트 PR 정리 스크립트

**기능:**
- ready-to-merge 레이블이 붙은 모든 열린 PR 닫기
- 관련 브랜치 삭제 (원격 및 로컬)
- test.txt 파일 복원 옵션

**사용법:**
```bash
./cleanup-test-prs.sh
```

## 워크플로우

### 테스트 워크플로우
```bash
# 1. 테스트 PR 생성
./create-test-prs.sh 3

# 2. Release 스크립트 테스트 (dry-run)
./create-release-server.sh --dry-run

# 3. 정리
./cleanup-test-prs.sh
```

### 실제 배포 워크플로우
```bash
# Server 배포
./create-release-server.sh

# Desktop 배포
./create-release-desktop.sh
```

## 주요 개선 사항 (이번 세션)

### ✅ create-release-server.sh
- **기존 릴리즈 브랜치 재사용 기능 추가**
  - 동일한 날짜의 릴리즈 브랜치가 이미 존재하는 경우 에러가 아닌 재사용
  - 충돌 해결 후 스크립트 재실행 가능
  - `BRANCH_EXISTS` 플래그를 사용하여 브랜치 상태 추적

### ✅ create-release-desktop.sh  
- **Desktop 브랜치 필터링**
  - `ready-to-merge` PR 중 `desktop/`로 시작하는 브랜치만 선택
  - Desktop 전용 배포 프로세스 지원


