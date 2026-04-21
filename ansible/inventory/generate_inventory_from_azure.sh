#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RG_NAME="${1:-}"
OUT_FILE="${2:-${SCRIPT_DIR}/hosts.ini}"

if [ -z "${RG_NAME}" ]; then
  echo "Usage: $0 <resource-group-name> [output-file]" >&2
  exit 1
fi

if ! command -v az >/dev/null 2>&1; then
  echo "az command not found." >&2
  exit 1
fi

PROXY_PUBLIC="$(az vm show -d -g "${RG_NAME}" -n vm-proxysql --query publicIps -o tsv)"
MASTER_PUBLIC="$(az vm show -d -g "${RG_NAME}" -n vm-db-master --query publicIps -o tsv)"

PROXY_PRIVATE="$(az vm show -d -g "${RG_NAME}" -n vm-proxysql --query privateIps -o tsv | awk '{print $1}')"
MASTER_PRIVATE="$(az vm show -d -g "${RG_NAME}" -n vm-db-master --query privateIps -o tsv | awk '{print $1}')"
SLAVE1_PRIVATE="$(az vm show -d -g "${RG_NAME}" -n vm-db-slave1 --query privateIps -o tsv | awk '{print $1}')"

require_non_empty() {
  local name="$1"
  local value="$2"
  if [ -z "${value}" ] || [ "${value}" = "null" ]; then
    echo "Missing value for ${name} from Azure in resource group ${RG_NAME}" >&2
    exit 1
  fi
}

require_non_empty "vm-proxysql.publicIps" "${PROXY_PUBLIC}"
require_non_empty "vm-db-master.publicIps" "${MASTER_PUBLIC}"
require_non_empty "vm-proxysql.privateIps" "${PROXY_PRIVATE}"
require_non_empty "vm-db-master.privateIps" "${MASTER_PRIVATE}"
require_non_empty "vm-db-slave1.privateIps" "${SLAVE1_PRIVATE}"

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

echo "Inventory generated from Azure at: ${OUT_FILE}"
