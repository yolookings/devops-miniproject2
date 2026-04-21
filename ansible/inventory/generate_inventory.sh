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

if [ -z "${TF_JSON}" ] || [ "${TF_JSON}" = "{}" ]; then
  cat >&2 <<'MSG'
Terraform output is empty ({}).
This usually happens when this clone does not have terraform.tfstate.

Options:
1) Copy/import the correct Terraform state, then rerun this script.
2) Create inventory manually from Azure IP/NIC values.
MSG
  exit 1
fi

PROXY_PUBLIC="$(jq -r '.proxy_public_ip.value' <<<"${TF_JSON}")"
PROXY_PRIVATE="$(jq -r '.proxy_private_ip.value' <<<"${TF_JSON}")"

MASTER_PUBLIC="$(jq -r '.db_public_ips.value.master' <<<"${TF_JSON}")"

MASTER_PRIVATE="$(jq -r '.db_private_ips.value.master' <<<"${TF_JSON}")"
SLAVE1_PRIVATE="$(jq -r '.db_private_ips.value.slave1' <<<"${TF_JSON}")"

require_non_null() {
  local name="$1"
  local value="$2"
  if [ -z "${value}" ] || [ "${value}" = "null" ]; then
    echo "Missing value for ${name}. Check Terraform outputs/state first." >&2
    exit 1
  fi
}

require_non_null "proxy_public_ip" "${PROXY_PUBLIC}"
require_non_null "proxy_private_ip" "${PROXY_PRIVATE}"
require_non_null "db_public_ips.master" "${MASTER_PUBLIC}"
require_non_null "db_private_ips.master" "${MASTER_PRIVATE}"
require_non_null "db_private_ips.slave1" "${SLAVE1_PRIVATE}"

cat > "${OUT_FILE}" <<INI
[app]
vm-proxysql ansible_host=${PROXY_PUBLIC} private_ip=${PROXY_PRIVATE}

[proxy]
vm-proxysql ansible_host=${PROXY_PUBLIC} private_ip=${PROXY_PRIVATE}

[db_master]
vm-db-master ansible_host=${MASTER_PUBLIC} private_ip=${MASTER_PRIVATE} mysql_server_id=101

[db_slaves]
vm-db-slave1 ansible_host=${SLAVE1_PRIVATE} private_ip=${SLAVE1_PRIVATE} mysql_server_id=102 ansible_ssh_common_args='-o ProxyJump=azureuser@${MASTER_PUBLIC}'

[db:children]
db_master
db_slaves

[all:vars]
ansible_user=azureuser
ansible_ssh_private_key_file=~/.ssh/id_rsa
ansible_python_interpreter=/usr/bin/python3
INI

echo "Inventory generated at: ${OUT_FILE}"
