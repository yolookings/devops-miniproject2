# DevOps Mini Project 2 — E-Commerce Database Architecture

Proyek ini merancang ulang arsitektur basis data e-commerce agar memiliki **high availability**, **read/write splitting** via ProxySQL, serta memenuhi standar keamanan melalui **enkripsi**, **firewalling**, dan **otomatisasi backup**.

## Arsitektur Sistem

```
                        ┌──────────────┐
                        │   App Node   │  ← Express.js (port 3000)
                        └──────┬───────┘
                               │
                        ┌──────▼───────┐
                        │   ProxySQL   │  ← Query Router (port 6033)
                        └──────┬───────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
       ┌──────▼──────┐ ┌──────▼──────┐ ┌───────▼─────┐
       │   Master    │ │   Slave 1   │ │   Slave 2   │
       │   (WRITE)   │ │   (READ)    │ │   (READ)    │
       └─────────────┘ └─────────────┘ └─────────────┘
```

## Project Structure

```
devops-miniproject2/
├── src/
│   └── index.js              # Express.js application
├── terraform/
│   ├── main.tf               # Provider & Resource Group
│   ├── variables.tf          # Input variables
│   ├── network.tf            # VNet, Subnets, NSGs (Firewall)
│   ├── vm-app.tf             # Application VM
│   ├── vm-proxysql.tf        # ProxySQL VM
│   ├── vm-db.tf              # 3 Database VMs (Master + 2 Slaves)
│   ├── outputs.tf            # Output IP addresses & SSH commands
│   └── terraform.tfvars      # Variable values (gitignored)
├── Dockerfile                # Multi-stage Docker build
├── .dockerignore             # Excludes files from build
├── package.json              # Node.js dependencies
└── README.md                 # This file
```

---

## Tahap 1: Kontainerisasi (Docker)

### Prerequisites

- Docker installed and running
- Trivy (atau Docker Scout) untuk vulnerability scanning

### Step 1: Build Docker Image

```bash
docker build -t ecommerce-app:1.0.0 .
```

### Step 2: Run the Container

```bash
docker run -d -p 3000:3000 --name ecommerce-app-test ecommerce-app:1.0.0

# Verify
docker ps
docker logs -f ecommerce-app-test
```

### Step 3: Test the Application

```bash
curl http://localhost:3000/health
# {"status":"healthy","timestamp":"2026-..."}
```

### Step 4: Vulnerability Scanning

```bash
# Menggunakan Trivy
trivy image --severity HIGH,CRITICAL ecommerce-app:1.0.0

# Atau menggunakan Docker Scout
docker scout cves ecommerce-app:1.0.0
```

### Step 5: Clean Up

```bash
docker stop ecommerce-app-test && docker rm ecommerce-app-test
```

### Application Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check (no DB required) |
| GET | `/api/products` | List products (READ → Slave) |
| POST | `/api/orders` | Create order (WRITE → Master) |
| GET | `/api/orders` | List orders (READ → Slave) |

### Dockerfile Features

- **Multi-stage build** — Reduces final image size
- **Alpine base image** — Minimal footprint (~170MB vs ~900MB)
- **Non-root user** — Runs as `nodejs` (uid 1001)
- **Health check** — Built-in container health monitoring
- **Layer caching** — Optimized for rebuild speed

### Scanning Results

| Image | OS Vulnerabilities | Status |
|-------|-------------------|--------|
| Node 18 Alpine | 11 (libcrypto3, libssl3, musl, zlib) | ❌ HIGH/CRITICAL |
| Node 22 Alpine | 0 | ✅ Clean |

---

## Tahap 2: Infrastructure as Code (Terraform)

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) (>= 1.0.0)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`)
- Azure subscription aktif
- SSH key pair (`~/.ssh/id_rsa` dan `~/.ssh/id_rsa.pub`)

### Arsitektur Azure

```
Azure Resource Group: rg-ecommerce-devops (Southeast Asia)
│
├── VNet: 10.0.0.0/16
│   ├── subnet-app   (10.0.1.0/24) → vm-app
│   ├── subnet-proxy (10.0.2.0/24) → vm-proxysql
│   └── subnet-db    (10.0.3.0/24) → vm-db-master, vm-db-slave1, vm-db-slave2
│
└── All VMs: Ubuntu 22.04 LTS, Standard_B1s, SSH key auth
```

### Network Security Groups (Firewall Rules)

Semua subnet memiliki **deny-all inbound** default. Hanya traffic berikut yang diizinkan:

| NSG | Rule | Source | Port | Keterangan |
|-----|------|--------|------|------------|
| **nsg-app** | Allow-SSH | Any | 22 | SSH management |
| | Allow-HTTP-App | Any | 3000 | Public access ke app |
| **nsg-proxy** | Allow-SSH | Any | 22 | SSH management |
| | Allow-MySQL-From-App | subnet-app | 6033 | App → ProxySQL |
| | Allow-Admin-From-App | subnet-app | 6032 | ProxySQL admin |
| **nsg-db** | Allow-SSH | Any | 22 | SSH management |
| | Allow-MySQL-From-Proxy | subnet-proxy | 3306 | ProxySQL → MySQL |
| | Allow-MySQL-Replication | subnet-db | 3306 | Master ↔ Slave |

### Terraform File Structure

| File | Deskripsi |
|------|-----------|
| `main.tf` | Azure provider config + Resource Group |
| `variables.tf` | Input variables (region, VM size, SSH key, CIDR blocks) |
| `network.tf` | VNet, 3 Subnets, 3 NSGs + firewall rules + associations |
| `vm-app.tf` | Application VM dengan Public IP |
| `vm-proxysql.tf` | ProxySQL VM dengan Public IP (SSH only) |
| `vm-db.tf` | 3 Database VMs via `for_each` (Master + 2 Slaves) |
| `outputs.tf` | Public/Private IPs + ready-to-use SSH commands |
| `terraform.tfvars` | Default variable values |

### Deploy ke Azure

```bash
cd terraform

# 1. Login ke Azure
az login

# 2. Initialize Terraform
terraform init

# 3. Preview infrastructure
terraform plan

# 4. Deploy
terraform apply

# 5. Lihat output (IP addresses, SSH commands)
terraform output
```

### Konfigurasi Variables

Edit `terraform/terraform.tfvars` sesuai kebutuhan:

```hcl
resource_group_name       = "rg-ecommerce-devops"
location                  = "southeastasia"
vm_size                   = "Standard_B1s"
admin_username            = "azureuser"
admin_ssh_public_key_path = "~/.ssh/id_rsa.pub"
```

### Setelah Deploy

Terraform akan menampilkan output berupa SSH commands untuk setiap VM:

```bash
ssh azureuser@<app-public-ip>
ssh azureuser@<proxy-public-ip>
ssh azureuser@<master-public-ip>
ssh azureuser@<slave1-public-ip>
ssh azureuser@<slave2-public-ip>
```

### Destroy Infrastructure

```bash
terraform destroy
```

---

## Environment Variables

```env
PORT=3000
DB_HOST=proxysql
DB_PORT=3306
DB_USER=appuser
DB_PASSWORD=apppassword
DB_NAME=ecommerce
```

## Next Stages

- **Tahap 3**: Ansible → Konfigurasi MySQL replication, SSL/TLS, automated backup
- **Tahap 4**: Monitoring & Logging
