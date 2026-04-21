#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${ROOT_DIR}/artifacts/security"

mkdir -p "${ARTIFACT_DIR}"

echo "[1/4] Build application image..."
docker build -t ecommerce-app:1.0.0 "${ROOT_DIR}"

echo "[2/4] Scan ecommerce-app image with Docker Scout..."
docker scout cves ecommerce-app:1.0.0 | tee "${ARTIFACT_DIR}/scout-ecommerce-app.txt"

echo "[3/4] Pull and scan ProxySQL image..."
docker pull proxysql/proxysql:2.6.2 >/dev/null
docker scout cves proxysql/proxysql:2.6.2 | tee "${ARTIFACT_DIR}/scout-proxysql.txt"

echo "[4/4] Quick HIGH/CRITICAL summary..."
{
  echo "=== ecommerce-app:1.0.0 ==="
  grep -Ei "critical|high|cve" "${ARTIFACT_DIR}/scout-ecommerce-app.txt" || true
  echo
  echo "=== proxysql/proxysql:2.6.2 ==="
  grep -Ei "critical|high|cve" "${ARTIFACT_DIR}/scout-proxysql.txt" || true
} | tee "${ARTIFACT_DIR}/scout-summary.txt"

echo
echo "Scan artifacts saved in: ${ARTIFACT_DIR}"
