#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# 테스트 PR 정리 스크립트
#
# ready-to-merge 레이블이 붙은 모든 열린 PR을 닫고
# 관련 브랜치를 삭제합니다.
#
# Usage:
#   ./cleanup-test-prs.sh
# ============================================================

echo "========================================="
echo " 테스트 PR 정리 스크립트"
echo "========================================="

# GitHub CLI 인증 확인
if ! gh auth status >/dev/null 2>&1; then
  echo "[ERROR] GitHub CLI 인증이 필요합니다."
  exit 1
fi

# ready-to-merge PR 목록 조회
echo ""
echo "ready-to-merge 레이블이 붙은 열린 PR 조회 중..."

PRS=$(gh pr list \
  --label "ready-to-merge" \
  --state open \
  --json number,title,headRefName \
  --template '{{range .}}{{.number}}|{{.title}}|{{.headRefName}}{{"\n"}}{{end}}')

if [[ -z "$PRS" ]]; then
  echo ""
  echo "정리할 PR이 없습니다."
  exit 0
fi

echo ""
echo "========================================="
echo " 정리할 PR 목록"
echo "========================================="
echo ""

while IFS="|" read -r NUMBER TITLE BRANCH; do
  echo "  - #${NUMBER} ${TITLE} [${BRANCH}]"
done <<< "$PRS"

echo ""
read -rp "위 PR들을 모두 닫고 브랜치를 삭제하시겠습니까? (y/n): " ANSWER

if [[ ! "$ANSWER" =~ ^[Yy]$ ]]; then
  echo "취소되었습니다."
  exit 0
fi

# PR 닫기 및 브랜치 삭제
echo ""
echo "========================================="
echo " 정리 시작"
echo "========================================="

CLOSED_COUNT=0

while IFS="|" read -r NUMBER TITLE BRANCH; do
  echo ""
  echo "PR #${NUMBER} 처리 중... [${BRANCH}]"

  # PR 닫기
  if gh pr close "${NUMBER}" --comment "🧹 테스트 PR 정리"; then
    echo "  ✓ PR #${NUMBER} 닫기 완료"

    # 원격 브랜치 삭제
    if git push origin --delete "${BRANCH}" 2>/dev/null; then
      echo "  ✓ 원격 브랜치 삭제 완료"
    else
      echo "  ⚠ 원격 브랜치 삭제 실패 (이미 삭제되었을 수 있음)"
    fi

    # 로컬 브랜치 삭제 (있는 경우)
    if git branch -D "${BRANCH}" 2>/dev/null; then
      echo "  ✓ 로컬 브랜치 삭제 완료"
    fi

    CLOSED_COUNT=$((CLOSED_COUNT + 1))
  else
    echo "  ✗ PR #${NUMBER} 닫기 실패"
  fi
done <<< "$PRS"

echo ""
echo "========================================="
echo " 정리 완료!"
echo " ${CLOSED_COUNT}개의 PR이 정리되었습니다."
echo "========================================="

# develop으로 돌아가기
git checkout develop 2>/dev/null || true

# test.txt 복원 (선택사항)
echo ""
read -rp "test.txt 파일을 원격의 최신 상태로 복원하시겠습니까? (y/n): " RESTORE

if [[ "$RESTORE" =~ ^[Yy]$ ]]; then
  git fetch origin develop
  git checkout origin/develop -- test.txt
  git add test.txt
  git commit -m "Restore test.txt after PR cleanup" || echo "복원할 변경사항이 없습니다."
  echo "test.txt 복원 완료"
fi

echo ""
echo "Done."

