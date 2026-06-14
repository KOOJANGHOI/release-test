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
# 7. 각 PR별 병합 여부 확인 (y/n)
# 8. 선택된 PR의 feature 브랜치를 release 브랜치에 Fast-Forward 병합
# 9. release 브랜치 push
# 10. release → develop PR 생성
# 11. 성공 / 실패 / 스킵 목록 출력
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
# Step 8. ready-to-merge PR 조회
#
echo ""
echo "[5/6] ready-to-merge PR 조회"

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

  echo ""
  echo "Release PR 생성"

  RELEASE_PR_URL=$(gh pr create \
    --base develop \
    --head "${RELEASE_BRANCH}" \
    --title "${RELEASE
