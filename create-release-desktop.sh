#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Desktop Release Branch 생성 및 Desktop 브랜치 병합 스크립트
#
# Usage:
#   ./create-release-desktop.sh             # 실제 운영 실행
#   ./create-release-desktop.sh --dry-run   # 모의 실행 (원격 반영 없음)
#
# 이 스크립트는 "desktop"으로 시작하는 브랜치만 병합합니다.
# (예: desktop/YYYYMMDD/개발자명)
# ============================================================

SUCCESS_PRS=()
FAILED_PRS=()
SKIPPED_PRS=()

RELEASE_PR_URL=""
DRY_RUN=false

# 입력 인자 확인 (--dry-run)
if [[ $# -gt 0 && "$1" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "========================================="
  echo " 🔥 DRY-RUN MODE (모의 실행 활성화)"
  echo " 실제 원격 push 및 GitHub PR 조작은 진행되지 않습니다."
  echo "========================================="
else
  echo "========================================="
  echo " Desktop Release Branch Automation (Squash Mode)"
  echo "========================================="
fi

#
# Step 1. GitHub CLI 인증 상태 확인
#
echo ""
echo "[Auth] GitHub CLI 인증 확인"

if ! gh auth status >/dev/null 2>&1; then
  echo "[ERROR] GitHub CLI 인증이 되어있지 않습니다."
  echo ""
  echo "아래 명령어로 로그인 후 다시 시도해주세요."
  echo ""
  echo "  gh auth login"
  exit 1
fi

#
# Step 2. 작업 트리 확인
#
if [[ -n "$(git status --porcelain)" ]]; then
  echo ""
  echo "[ERROR] 작업 중인 변경사항이 존재합니다."
  echo "커밋 또는 stash 후 다시 실행해주세요."
  exit 1
fi

#
# Step 3. 배포일 입력
#
echo ""
read -rp "배포일을 입력하세요 (YYYYMMDD): " RELEASE_DATE

if [[ ! "$RELEASE_DATE" =~ ^[0-9]{8}$ ]]; then
  echo "[ERROR] YYYYMMDD 형식으로 입력해주세요."
  exit 1
fi

RELEASE_BRANCH="release/${RELEASE_DATE}"

echo ""
echo "Release Branch : ${RELEASE_BRANCH}"

#
# Step 4. develop 최신화
#
echo ""
echo "[1/6] develop 최신화"

git checkout develop
git fetch origin
git reset --hard origin/develop

#
# Step 5. release 브랜치 존재 여부 확인
#
echo ""
echo "[2/6] release 브랜치 확인"

BRANCH_EXISTS=false
if git ls-remote --heads origin "${RELEASE_BRANCH}" | grep -q "${RELEASE_BRANCH}"; then
  echo "[INFO] 이미 존재하는 release 브랜치입니다. 기존 브랜치를 사용합니다."
  BRANCH_EXISTS=true
fi

#
# Step 6. release 브랜치 생성 또는 체크아웃
#
echo ""
echo "[3/6] release 브랜치 생성/체크아웃"

if [ "$BRANCH_EXISTS" = true ]; then
  git fetch origin "${RELEASE_BRANCH}"
  git checkout "${RELEASE_BRANCH}"
  git reset --hard "origin/${RELEASE_BRANCH}"
else
  git checkout -b "${RELEASE_BRANCH}"
fi

#
# Step 7. release 브랜치 push
#
echo ""
echo "[4/6] release 브랜치 push"

if [ "$DRY_RUN" = true ]; then
  echo "[DRY-RUN] git push -u origin ${RELEASE_BRANCH} (건너뜀)"
else
  if [ "$BRANCH_EXISTS" = true ]; then
    echo "[INFO] 기존 브랜치이므로 push 단계를 건너뜁니다."
  else
    git push -u origin "${RELEASE_BRANCH}"
  fi
fi

#
# Step 8. desktop 브랜치가 있는 ready-to-merge PR 조회
#
echo ""
echo "[5/6] desktop 브랜치의 ready-to-merge PR 조회"

ALL_PRS=$(gh pr list \
  --label "ready-to-merge" \
  --state open \
  --json number,title,headRefName \
  --template '{{range .}}{{.number}}|{{.title}}|{{.headRefName}}{{"\n"}}{{end}}')

# desktop으로 시작하는 브랜치만 필터링
PRS=""
if [[ -n "$ALL_PRS" ]]; then
  while IFS="|" read -r NUMBER TITLE BRANCH; do
    if [[ "$BRANCH" =~ ^desktop/ ]]; then
      if [[ -z "$PRS" ]]; then
        PRS="${NUMBER}|${TITLE}|${BRANCH}"
      else
        PRS="${PRS}"$'\n'"${NUMBER}|${TITLE}|${BRANCH}"
      fi
    fi
  done <<< "$ALL_PRS"
fi

if [[ -z "$PRS" ]]; then
  echo ""
  echo "병합 대상 Desktop PR이 없습니다."
  echo ""
  echo "Release PR 생성"

  if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] gh pr create --base develop --head ${RELEASE_BRANCH} (건너뜀)"
    RELEASE_PR_URL="(dry-run-url)"
  else
    RELEASE_PR_URL=$(gh pr create \
      --base develop \
      --head "${RELEASE_BRANCH}" \
      --title "${RELEASE_BRANCH}" \
      --body-file /dev/null)
  fi

  echo "PR Created: ${RELEASE_PR_URL}"
  exit 0
fi

echo ""
echo "========================================="
echo " Desktop Release Plan"
echo "========================================="
echo ""
echo "Release Branch : ${RELEASE_BRANCH}"
echo ""

while IFS="|" read -r NUMBER TITLE BRANCH; do
  echo "  - #${NUMBER} ${TITLE} [${BRANCH}]"
done <<< "$PRS"

#
# Step 9. PR 병합 및 즉시 Close
#
echo ""
echo "========================================="
echo " Merge Start"
echo "========================================="

while IFS="|" read -u 3 -r NUMBER TITLE BRANCH; do

  echo ""
  echo "-----------------------------------------"
  echo "PR      : #${NUMBER}"
  echo "Title   : ${TITLE}"
  echo "Branch  : ${BRANCH}"
  echo "-----------------------------------------"

  read -rp "이 PR을 release에 병합하시겠습니까? (y/n): " ANSWER

  if [[ ! "$ANSWER" =~ ^[Yy]$ ]]; then
    echo "[SKIPPED]"
    SKIPPED_PRS+=("#${NUMBER} (${BRANCH})")
    continue
  fi

  # 최신 원격 정보 가져오기
  git fetch origin "${BRANCH}"

  # release 브랜치로 이동
  git checkout "${RELEASE_BRANCH}"

  # Squash 병합 시도
  if git merge --squash "origin/${BRANCH}"; then

    # 로컬 커밋은 dry-run이든 아니든 진행하여 병합 성공 여부(충돌 체크) 확인
    git commit -m "${TITLE} (#${NUMBER})"

    SUCCESS_PRS+=("#${NUMBER} (${BRANCH})")
    echo "[SUCCESS] 로컬 Squash 병합 및 표준 커밋 완료"

    # 깃허브 조작 부분만 dry-run 제어
    if [ "$DRY_RUN" = true ]; then
      echo "[DRY-RUN] GitHub PR #${NUMBER} Close 및 댓글 작성 (건너뜀)"
    else
      echo "GitHub PR #${NUMBER} Close 처리 중..."
      gh pr comment "${NUMBER}" --body "🚀 이 PR은 배포본 \`${RELEASE_BRANCH}\`에 Squash 병합되어 Close 처리되었습니다."
      gh pr close "${NUMBER}"
    fi
  else
    FAILED_PRS+=("#${NUMBER} (${BRANCH})")
    echo "[FAILED] Merge Conflict 발생 (인간이 해결해야 함)"
    git merge --abort || true
  fi

done 3<<< "$PRS"

#
# Step 10. release 브랜치 push
#
echo ""
echo "[6/6] release 브랜치 push"

if [[ ${#SUCCESS_PRS[@]} -gt 0 ]]; then
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] git push origin ${RELEASE_BRANCH} (건너뜀)"
  else
    git push origin "${RELEASE_BRANCH}"
  fi
else
  echo "병합에 성공한 PR이 없어 원격 push를 건너뜁니다."
fi

#
# Step 11. release -> develop PR 생성
#
echo ""
echo "Create Release PR"

if [[ ${#SUCCESS_PRS[@]} -gt 0 ]]; then
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] gh pr create --base develop --head ${RELEASE_BRANCH} (건너뜀)"
    RELEASE_PR_URL="(dry-run-release-pr-url)"
  else
    RELEASE_PR_URL=$(gh pr create \
      --base develop \
      --head "${RELEASE_BRANCH}" \
      --title "${RELEASE_BRANCH}" \
      --body-file /dev/null)
  fi
  echo "PR Created: ${RELEASE_PR_URL}"
else
  echo "[SKIP] 변경된 커밋이 없으므로 Release PR 생성을 건너뜁니다."
  RELEASE_PR_URL="(none)"
fi

# 모의 실행인 경우, 로컬에 생성된 배포 브랜치 흔적 지우기 및 복구
if [ "$DRY_RUN" = true ]; then
  echo ""
  echo "[DRY-RUN] 모의 실행이 끝나 로컬 환경을 원상복구합니다."
  git checkout develop
  git branch -D "${RELEASE_BRANCH}" >/dev/null 2>&1 || true
fi

#
# Result
#
echo ""
echo "========================================="
echo " Result"
if [ "$DRY_RUN" = true ]; then
  echo " (⚠️ DRY-RUN MODE RESULTS - NO ACTUAL CHANGES)"
fi
echo "========================================="

echo ""
echo "[SUCCESS]"
if [[ ${#SUCCESS_PRS[@]} -eq 0 ]]; then
  echo "  (none)"
else
  for item in "${SUCCESS_PRS[@]}"; do
    echo "  - ${item}"
  done
fi

echo ""
echo "[FAILED]"
if [[ ${#FAILED_PRS[@]} -eq 0 ]]; then
  echo "  (none)"
else
  for item in "${FAILED_PRS[@]}"; do
    echo "  - ${item}"
  done
fi

echo ""
echo "[SKIPPED]"
if [[ ${#SKIPPED_PRS[@]} -eq 0 ]]; then
  echo "  (none)"
else
  for item in "${SKIPPED_PRS[@]}"; do
    echo "  - ${item}"
  done
fi

echo ""
echo "Release Branch : ${RELEASE_BRANCH}"
echo ""
echo "Release PR"
echo "  ${RELEASE_PR_URL}"
echo ""
echo "Done."

