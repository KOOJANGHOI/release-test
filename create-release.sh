#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Release Branch 생성 및 Ready-To-Merge PR 병합 스크립트
#
# Workflow
#
# 1. GitHub CLI 인증 상태 확인
# 2. 작업 트리가 깨끗한지 확인
# 3. develop 최신화
# 4. release/YYYYMMDD 생성
# 5. release 브랜치 원격 저장소 push
# 6. ready-to-merge 라벨이 붙은 PR 조회
# 7. 사용자 확인 (Continue? y/n)
# 8. 각 PR의 feature 브랜치를 release 브랜치에 병합 시도
# 9. release 브랜치 push
# 10. 성공 / 실패 목록 출력
#
# Requirements
#
# - git
# - gh cli
# - gh auth login 완료 상태
#
# ============================================================

SUCCESS_PRS=()
FAILED_PRS=()

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

RELEASE_BRANCH="release/${RELEASE_DATE}"

echo ""
echo "Release Branch : ${RELEASE_BRANCH}"

#
# Step 4. develop 최신화
#
echo ""
echo "[1/5] develop 최신화"

git checkout develop
git fetch origin
git reset --hard origin/develop

#
# Step 5. release 브랜치 존재 여부 확인
#
echo ""
echo "[2/5] release 브랜치 확인"

if git ls-remote --heads origin "${RELEASE_BRANCH}" | grep -q "${RELEASE_BRANCH}"; then
  echo "[ERROR] 이미 존재하는 release 브랜치입니다."
  exit 1
fi

#
# Step 6. release 브랜치 생성
#
echo ""
echo "[3/5] release 브랜치 생성"

git checkout -b "${RELEASE_BRANCH}"

#
# Step 7. release 브랜치 push
#
echo ""
echo "[4/5] release 브랜치 push"

git push -u origin "${RELEASE_BRANCH}"

#
# Step 8. ready-to-merge PR 조회
#
echo ""
echo "[5/5] ready-to-merge PR 조회"

PRS=$(
  gh pr list \
    --label "ready-to-merge" \
    --state open \
    --json number,title,headRefName \
    --template '{{range .}}{{.number}}|{{.title}}|{{.headRefName}}{{"\n"}}{{end}}'
)

if [[ -z "$PRS" ]]; then
  echo ""
  echo "병합 대상 PR이 없습니다."
  exit 0
fi

#
# Continue 확인
#
echo ""
echo "========================================="
echo " Release Plan"
echo "========================================="
echo ""
echo "Release Branch : ${RELEASE_BRANCH}"
echo ""
echo "병합 대상 PR"

while IFS='|' read -r NUMBER TITLE BRANCH; do
  echo "  - #${NUMBER} ${TITLE} [${BRANCH}]"
done <<< "$PRS"

echo ""
read -rp "계속 진행하시겠습니까? (y/n): " ANSWER

if [[ ! "$ANSWER" =~ ^[Yy]$ ]]; then
  echo ""
  echo "작업이 취소되었습니다."
  exit 0
fi

#
# Step 9. PR 병합
#
echo ""
echo "========================================="
echo " Merge Start"
echo "========================================="

while IFS='|' read -r NUMBER TITLE BRANCH; do

  echo ""
  echo "-----------------------------------------"
  echo "PR      : #${NUMBER}"
  echo "Title   : ${TITLE}"
  echo "Branch  : ${BRANCH}"
  echo "-----------------------------------------"

  #
  # 최신 원격 정보 가져오기
  #
  git fetch origin "${BRANCH}"

  #
  # release 브랜치로 이동
  #
  git checkout "${RELEASE_BRANCH}"

  #
  # 병합 시도
  #
  if git merge --no-ff "origin/${BRANCH}" -m "Merge PR #${NUMBER}: ${TITLE}"; then

    SUCCESS_PRS+=("#${NUMBER} (${BRANCH})")

    echo "[SUCCESS]"

  else

    FAILED_PRS+=("#${NUMBER} (${BRANCH})")

    echo "[FAILED] Merge Conflict"

    git merge --abort || true

  fi

done <<< "$PRS"

#
# Step 10. release 브랜치 push
#
echo ""
echo "Push Release Branch"

git push origin "${RELEASE_BRANCH}"

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
echo "Release Branch : ${RELEASE_BRANCH}"
echo ""
echo "Done."
