#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TF_DIR="${1:-${ROOT_DIR}/terraform}"
OUT_FILE="${2:-${SCRIPT_DIR}/hosts.ini}"

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform command not found." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq command not found." >&2
  exit 1
fi

if [ ! -d "${TF_DIR}" ]; then
  echo "Terraform directory not found: ${TF_DIR}" >&2
  exit 1
fi

TF_JSON="$(terraform -chdir="${TF_DIR}" output -json)"

APP_PUBLIC="$(jq -r '.app_public_ip.value' <<<"${TF_JSON}")"
APP_PRIVATE="$(jq -r '.app_private_ip.value' <<<"${TF_JSON}")"

PROXY_PUBLIC="$(jq -r '.proxy_public_ip.value' <<<"${TF_JSON}")"
PROXY_PRIVATE="$(jq -r '.proxy_private_ip.value' <<<"${TF_JSON}")"

MASTER_PUBLIC="$(jq -r '.db_public_ips.value.master' <<<"${TF_JSON}")"

MASTER_PRIVATE="$(jq -r '.db_private_ips.value.master' <<<"${TF_JSON}")"
SLAVE1_PRIVATE="$(jq -r '.db_private_ips.value.slave1' <<<"${TF_JSON}")"
SLAVE2_PRIVATE="$(jq -r '.db_private_ips.value.slave2' <<<"${TF_JSON}")"

cat > "${OUT_FILE}" <<INI
[app]
vm-app ansible_host=${APP_PUBLIC} private_ip=${APP_PRIVATE}

[proxy]
vm-proxysql ansible_host=${PROXY_PUBLIC} private_ip=${PROXY_PRIVATE}

[db_master]
vm-db-master ansible_host=${MASTER_PUBLIC} private_ip=${MASTER_PRIVATE} mysql_server_id=101

[db_slaves]
vm-db-slave1 ansible_host=${SLAVE1_PRIVATE} private_ip=${SLAVE1_PRIVATE} mysql_server_id=102 ansible_ssh_common_args='-o ProxyJump=azureuser@${MASTER_PUBLIC}'
vm-db-slave2 ansible_host=${SLAVE2_PRIVATE} private_ip=${SLAVE2_PRIVATE} mysql_server_id=103 ansible_ssh_common_args='-o ProxyJump=azureuser@${MASTER_PUBLIC}'

[db:children]
db_master
db_slaves

[all:vars]
ansible_user=azureuser
ansible_ssh_private_key_file=~/.ssh/id_rsa
ansible_python_interpreter=/usr/bin/python3
INI

echo "Inventory generated at: ${OUT_FILE}"
