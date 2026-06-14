#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Release Branch 생성 및 Ready-To-Merge PR 병합 스크립트
# ============================================================

SUCCESS_PRS=()
FAILED_PRS=()
SKIPPED_PRS=()

RELEASE_PR_URL=""

echo "========================================="
echo " Release Branch Automation"
echo "========================================="

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

if git ls-remote --heads origin "${RELEASE_BRANCH}" | grep -q "${RELEASE_BRANCH}"; then
  echo "[ERROR] 이미 존재하는 release 브랜치입니다."
  exit 1
fi

#
# Step 6. release 브랜치 생성
#
echo ""
echo "[3/6] release 브랜치 생성"

git checkout -b "${RELEASE_BRANCH}"

#
# Step 7. release 브랜치 push
#
echo ""
echo "[4/6] release 브랜치 push"

git push -u origin "${RELEASE_BRANCH}"

#
# Step 8. ready-to-merge PR 조회 (템플릿 따옴표 완벽 격리)
#
echo ""
echo "[5/6] ready-to-merge PR 조회"

# 템플릿 안의 뉴라인 처리를 고정 문자열로 변경하여 Bash 파싱 에러 원천 차단
PRS=$(gh pr list \
  --label "ready-to-merge" \
  --state open \
  --json number,title,headRefName \
  --template '{{range .}}{{.number}}|{{.title}}|{{.headRefName}}{{"\n"}}{{end}}')

if [[ -z "$PRS" ]]; then
  echo ""
  echo "병합 대상 PR이 없습니다."
  echo ""
  echo "Release PR 생성"

  RELEASE_PR_URL=$(gh pr create \
    --base develop \
    --head "${RELEASE_BRANCH}" \
    --title "${RELEASE_BRANCH}" \
    --body-file /dev/null)

  echo "PR Created: ${RELEASE_PR_URL}"
  exit 0
fi

echo ""
echo "========================================="
echo " Release Plan"
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

  # 병합 시도 (Fast-Forward 전략 사용)
  if git merge --ff-only "origin/${BRANCH}"; then
    SUCCESS_PRS+=("#${NUMBER} (${BRANCH})")
    echo "[SUCCESS] 로컬 병합 완료"

    # 깃허브 PR 즉시 Close (원격 브랜치는 유지)
    echo "GitHub PR #${NUMBER} Close 처리 중..."
    gh pr comment "${NUMBER}" --body "🚀 이 PR은 배포본 \`${RELEASE_BRANCH}\`에 성공적으로 병합되어 Close 처리되었습니다."
    gh pr close "${NUMBER}"
  else
    FAILED_PRS+=("#${NUMBER} (${BRANCH})")
    echo "[FAILED] Fast-Forward Merge 불가 (충돌 또는 히스토리 불일치)"
    git merge --abort || true
  fi

done 3<<< "$PRS"

#
# Step 10. release 브랜치 push
#
echo ""
echo "[6/6] release 브랜치 push"

git push origin "${RELEASE_BRANCH}"

#
# Step 11. release -> develop PR 생성
#
echo ""
echo "Create Release PR"

RELEASE_PR_URL=$(gh pr create \
  --base develop \
  --head "${RELEASE_BRANCH}" \
  --title "${RELEASE_BRANCH}" \
  --body-file /dev/null)

echo "PR Created: ${RELEASE_PR_URL}"

#
# Result
#
echo ""
echo "========================================="
echo " Result"
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
