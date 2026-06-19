#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# 테스트용 ready-to-merge PR 생성 스크립트
#
# Usage:
#   ./create-test-prs.sh <개수>
#   ./create-test-prs.sh 5  # 5개의 PR 생성
# ============================================================

# PR 개수 입력
PR_COUNT=${1:-3}

echo "========================================="
echo " 테스트 PR 생성 스크립트"
echo " 생성할 PR 개수: ${PR_COUNT}"
echo "========================================="

# GitHub CLI 인증 확인
if ! gh auth status >/dev/null 2>&1; then
  echo "[ERROR] GitHub CLI 인증이 필요합니다."
  exit 1
fi

# develop 브랜치로 이동 및 최신화
echo ""
echo "develop 브랜치 최신화..."
git checkout develop
git fetch origin
git reset --hard origin/develop

# PR 생성 루프
for i in $(seq 1 $PR_COUNT); do
  TIMESTAMP=$(date +%s)
  BRANCH_NAME="feature/test-pr-${TIMESTAMP}-${i}"

  echo ""
  echo "========================================="
  echo " PR ${i}/${PR_COUNT} 생성 중..."
  echo " Branch: ${BRANCH_NAME}"
  echo "========================================="

  # 브랜치 생성
  git checkout -b "${BRANCH_NAME}"

  # test.txt 파일 수정
  echo "" >> test.txt
  echo "Test PR #${i} - ${TIMESTAMP}" >> test.txt
  echo "This is a test commit for PR automation testing" >> test.txt

  # 커밋
  git add test.txt
  git commit -m "Test PR #${i}: Add test content to test.txt"

  # 원격 푸시
  git push -u origin "${BRANCH_NAME}"

  # PR 생성 (ready-to-merge 레이블 추가)
  PR_URL=$(gh pr create \
    --base develop \
    --head "${BRANCH_NAME}" \
    --title "Test PR #${i}: Add test content" \
    --body "This is a test PR for automation testing. Branch: ${BRANCH_NAME}" \
    --label "ready-to-merge")

  echo "[SUCCESS] PR 생성 완료: ${PR_URL}"

  # develop으로 돌아가기
  git checkout develop

  # 짧은 대기 (GitHub API rate limit 방지)
  sleep 1
done

echo ""
echo "========================================="
echo " 완료!"
echo " ${PR_COUNT}개의 PR이 생성되었습니다."
echo "========================================="
echo ""
echo "생성된 PR 확인:"
gh pr list --label "ready-to-merge" --state open

echo ""
echo "테스트 후 정리하려면:"
echo "  ./cleanup-test-prs.sh"

