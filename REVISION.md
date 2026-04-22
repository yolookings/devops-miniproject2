# 📋 Revision Demo Guide — Mini Project 2

List Yang Perlu Di Revisi :

- Menunjukkan security (user, privilege, firewall, port DB)
- Menunjukkan backup SQL (manual & otomatis)
- Menunjukkan perbedaan hak akses master dan slave
- Menunjukkan status replikasi master-slave
- Menunjukkan konfigurasi cron job backup database
- Menunjukkan hasil backup otomatis dari cron

---

## 📌 INFO VM

| VM        | Public IP      | SSH Command                                          |
| :-------- | :------------- | :--------------------------------------------------- |
| Proxy/App | 13.70.31.205   | `ssh azureuser@13.70.31.205`                         |
| Master DB | 104.208.76.221 | `ssh azureuser@104.208.76.221`                       |
| Slave DB  | (via Proxy)    | `ssh -J azureuser@104.208.76.221 azureuser@10.0.3.5` |

---

## 1. 🔒 KEAMANAN (NSG Firewall)

### Implementasi

Keamanan jaringan diimplementasikan menggunakan **Azure NSG (Network Security Group)** yang dikonfigurasi via Terraform di file `terraform/network.tf`.

**Prinsip utama:**

- DB hanya bisa diakses dari subnet ProxySQL (`10.0.2.x`) — port 3306 **tidak** terbuka ke publik
- ProxySQL port 6033 hanya bisa diakses dari App subnet (`10.0.1.x`)
- Semua traffic yang tidak diizinkan secara eksplisit diblokir oleh rule `Deny-All-Inbound` (priority 4096)

**Source code — `terraform/network.tf`:**

```hcl
# NSG Database: hanya izinkan MySQL dari ProxySQL subnet
security_rule {
  name                       = "Allow-MySQL-From-Proxy"
  priority                   = 110
  destination_port_range     = "3306"
  source_address_prefix      = var.subnet_proxy_prefix  # 10.0.2.0/24
}

# Deny semua traffic lain
security_rule {
  name      = "Deny-All-Inbound"
  priority  = 4096
  access    = "Deny"
}
```

### Demo Uji Coba

**Test 1 — Akses DB langsung dari internet (HARUS GAGAL):**

```bash
mysql -h 104.208.76.221 -u appuser -pAppPass_ChangeMe_123! -P 3306
```

> ✅ **Hasil yang benar:** `ERROR 2003 (HY000): Can't connect to MySQL server` — NSG memblokir port 3306 dari luar.

**Test 2 — Akses lewat ProxySQL (HARUS BERHASIL):**

```bash
mysql -h 13.70.31.205 -u appuser -pAppPass_ChangeMe_123! -P 6033
```

> ✅ **Hasil yang benar:** Login berhasil — ProxySQL sebagai satu-satunya pintu masuk.

---

## 2. 🔐 KEAMANAN TAMBAHAN: SSL/TLS Antar Node

### Implementasi

Selain NSG, semua komunikasi antar node **dienkripsi menggunakan SSL/TLS** dengan sertifikat custom CA.

**Source code — `ansible/roles/mysql/templates/mysql-replication.cnf.j2`:**

```ini
require_secure_transport = ON          # Wajib SSL untuk semua koneksi
ssl-ca   = /etc/mysql/ssl/ca.pem
ssl-cert = /etc/mysql/ssl/server-cert.pem
ssl-key  = /etc/mysql/ssl/server-key.pem
```

**Source code — `ansible/roles/mysql/tasks/main.yml`** (saat buat user):

```sql
ALTER USER 'repl_user'@'10.0.3.%' REQUIRE SSL;
ALTER USER 'appuser'@'10.0.2.%'   REQUIRE SSL;
ALTER USER 'monitor_user'@'10.0.2.%' REQUIRE SSL;
```

Bukti sertifikat tersimpan di:

- `ansible/artifacts/certs/ca.pem`
- `ansible/artifacts/certs/vm-db-master-cert.pem`
- `ansible/artifacts/certs/vm-db-slave1-cert.pem`
- `ansible/artifacts/certs/vm-proxysql-cert.pem`

---

## 3. 💾 BACKUP SQL

### Implementasi

Backup dikonfigurasi via Ansible role `backup` menggunakan script `mysqldump` yang di-deploy ke Master DB.

**Source code — `ansible/roles/backup/templates/mysql-backup.sh.j2`:**

```bash
BACKUP_DIR="/var/backups/mysql"
TIMESTAMP="$(date +%F_%H-%M-%S)"
BACKUP_FILE="${BACKUP_DIR}/ecommerce_${TIMESTAMP}.sql.gz"

# Backup + compress langsung
mysqldump --protocol=socket -uroot \
  --single-transaction --quick --routines --triggers \
  ecommerce | gzip > "${BACKUP_FILE}"

# Auto-delete backup lebih dari 7 hari
find "${BACKUP_DIR}" -type f -name '*.sql.gz' -mtime +7 -delete
```

**Source code — `ansible/roles/backup/tasks/main.yml`:**

```yaml
- name: Install backup script
  ansible.builtin.template:
    src: mysql-backup.sh.j2
    dest: /opt/mysql-backup/mysql-backup.sh
    mode: "0750"

- name: Create daily cronjob for MySQL backup
  ansible.builtin.cron:
    minute: "0"
    hour: "2"
    job: "/opt/mysql-backup/mysql-backup.sh >> /var/log/mysql-backup.log 2>&1"
```

### Demo Uji Coba

```bash
# SSH ke Master DB
ssh azureuser@104.208.76.221

# Jalankan backup manual
sudo /opt/mysql-backup/mysql-backup.sh

# Cek hasil backup
ls -lh /var/backups/mysql/

# lihat file
zcat /var/backups/mysql/(nama file) | head -n 20
```

> ✅ **Hasil yang benar:** Muncul file seperti `ecommerce_2025-04-22_02-00-00.sql.gz`

---

## 4. ⏰ CRON JOB (Backup Otomatis)

### Implementasi

Cron job dibuat otomatis oleh Ansible (lihat source `backup/tasks/main.yml` di atas).

**Jadwal:** Setiap hari pukul **02:00 dini hari** — `0 2 * * *`

### Demo Uji Coba

```bash
# SSH ke Master DB
ssh azureuser@104.208.76.221

# Lihat jadwal cron
sudo crontab -l
```

> ✅ **Hasil yang benar:**
>
> ```
> 0 2 * * * /opt/mysql-backup/mysql-backup.sh >> /var/log/mysql-backup.log 2>&1
> ```

---

## 5. 🔄 HAK AKSES BERBEDA (Master vs Slave)

### Implementasi

Master dan Slave dikonfigurasi dengan hak akses yang berbeda melalui dua mekanisme:

**A. MySQL `read_only` — `ansible/roles/mysql/templates/mysql-replication.cnf.j2`:**

```ini
read_only       = {{ 'OFF' if inventory_hostname in groups['db_master'] else 'ON' }}
super_read_only = {{ 'OFF' if inventory_hostname in groups['db_master'] else 'ON' }}
```

- **Master:** `read_only = OFF` → bisa tulis
- **Slave:** `read_only = ON` + `super_read_only = ON` → hanya bisa baca

**B. ProxySQL Query Routing — `ansible/roles/proxysql/templates/proxysql-bootstrap.sql.j2`:**

```sql
-- Master = Hostgroup 10 (WRITE)
INSERT INTO mysql_servers(hostgroup_id, ...) VALUES (10, 'master_ip', ...);

-- Slave  = Hostgroup 20 (READ)
INSERT INTO mysql_servers(hostgroup_id, ...) VALUES (20, 'slave_ip', ...);

-- Query rule: SELECT → Slave (HG 20)
INSERT INTO mysql_query_rules(rule_id, match_pattern, destination_hostgroup)
VALUES (110, '^SELECT', 20);

-- SELECT FOR UPDATE → Master (HG 10)
INSERT INTO mysql_query_rules(rule_id, match_pattern, destination_hostgroup)
VALUES (100, '^SELECT .* FOR UPDATE', 10);
```

## Demo Uji Coba

- Test Write

```sh
# ssh ke master
ssh azureuser@104.208.76.221

# write
mysql -h 127.0.0.1 -u appuser -pAppPass_ChangeMe_123! -P 6033 -e "INSERT INTO ecommerce.products (name, price, stock) VALUES ('ProdukDemo', 50000, 10);"

# read
mysql -h 127.0.0.1 -u appuser -pAppPass_ChangeMe_123! -P 6033 -e "SELECT * FROM ecommerce.products WHERE name='ProdukDemo';"
```

- Test Read

```sh
# Masuk ke Slave Lewat Proxy
ssh -J azureuser@104.208.76.221 azureuser@10.0.3.5

# masukan command write
sudo mysql -e "INSERT INTO ecommerce.products (name, price, stock) VALUES ('Test', 1, 1);"

# Test Read
sudo mysql -e "SELECT * FROM ecommerce.products;"
```

## 6. 🔁 REPLIKASI MySQL (Master-Slave)

### Implementasi

Replikasi menggunakan **GTID (Global Transaction ID)** + **SSL** — `ansible/roles/mysql/tasks/main.yml`:

```yaml
# Konfigurasi slave
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='10.0.3.4',
  SOURCE_AUTO_POSITION=1,   # GTID mode
  SOURCE_SSL=1,
  SOURCE_SSL_CA='/etc/mysql/ssl/ca.pem';
START REPLICA;
```

### Demo Uji Coba

```bash
# Cek status replikasi dari Slave
ssh -J azureuser@104.208.76.221 azureuser@10.0.3.5
sudo mysql -e "SHOW REPLICA STATUS\G" | grep -E "Running|Seconds_Behind"
```

> ✅ **Hasil yang benar:**
>
> ```
> Replica_IO_Running: Yes
> Replica_SQL_Running: Yes
> Seconds_Behind_Source: 0
> ```

---

## 🚀 Quick Check Semua Sekaligus

Copy-paste ke terminal lokal kamu:

```bash
# 1. CEK FILE BACKUP
echo "=== BACKUP FILES ===" && \
ssh azureuser@20.24.87.253 "ls -lh /var/backups/mysql/"

# 2. CEK JADWAL CRON
echo "=== CRON JOB ===" && \
ssh azureuser@20.24.87.253 "sudo crontab -l"

# 3. CEK REPLIKASI (Running = Yes)
echo "=== REPLICATION STATUS ===" && \
ssh -J azureuser@20.205.34.115 azureuser@10.0.3.5 \
  "sudo mysql -e 'SHOW REPLICA STATUS\G'" | grep -E "Running|Behind"

# 4. CEK PROXYSQL SERVER LIST
echo "=== PROXYSQL SERVERS ===" && \
ssh azureuser@20.205.34.115 \
  "mysql -uadmin -padmin -h127.0.0.1 -P6032 \
   -e 'SELECT hostgroup_id, hostname, status FROM mysql_servers;'"
```

---

## 📁 Struktur Project

```
mini-project2/
├── terraform/              # Provisioning infrastruktur Azure
│   ├── network.tf          # NSG firewall rules ← KEAMANAN
│   ├── vm-db.tf            # VM Master & Slave DB
│   └── vm-proxysql.tf      # VM ProxySQL
├── ansible/
│   ├── roles/
│   │   ├── mysql/
│   │   │   ├── tasks/main.yml              # Setup MySQL + replikasi
│   │   │   └── templates/
│   │   │       └── mysql-replication.cnf.j2 ← READ_ONLY slave
│   │   ├── backup/
│   │   │   ├── tasks/main.yml              # Cron job setup ← CRON
│   │   │   └── templates/
│   │   │       └── mysql-backup.sh.j2      ← BACKUP SCRIPT
│   │   └── proxysql/
│   │       ├── tasks/main.yml              # Deploy ProxySQL container
│   │       └── templates/
│   │           └── proxysql-bootstrap.sql.j2 ← READ/WRITE SPLIT
│   └── artifacts/certs/    # SSL certificates untuk semua node
├── src/index.js            # Node.js app (Express + mysql2)
└── Dockerfile              # Container image app
```
