# Revision Demo Guide

Commands and step-by-step workflow to demonstrate all required aspects during revision presentation.

---

## Demo Overview

| #   | Aspect to Demonstrate   | Command                    | Expected Result                        |
| --- | ----------------------- | -------------------------- | -------------------------------------- |
| 1   | Security (NSG Firewall) | Show Azure Portal/CLI      | Firewall rules block untrusted traffic |
| 2   | SQL Backup              | Run mysqldump              | `.sql.gz` file created                 |
| 3   | Access Rights           | Compare Master vs Slave    | Different permissions                  |
| 4   | Backup File             | List `/var/backups/mysql/` | Backup files present                   |
| 5   | Cron Job                | `crontab -l`               | Scheduled backup job                   |

---

## VM Access Information

For your demo, note these credentials:

| VM        | Hostname     | Public IP         | SSH Command                                       |
| --------- | ------------ | ----------------- | ------------------------------------------------- |
| App+Proxy | vm-app-proxy | **4.193.169.206** | `ssh azureuser@4.193.169.206`                     |
| DB Master | vm-master-db | **4.194.58.44**   | `ssh azureuser@4.194.58.44`                       |
| DB Slave  | vm-slave-db  | (via jump)        | `ssh -J azureuser@4.194.58.44 azureuser@10.0.3.4` |

---

## Demo 1: Security Implementation

### Show NSG (Network Security Group) Rules

```bash
# On your local machine (has Azure CLI)
az vm list -g "$RG" -d -o table
az network nsg list --resource-group rg-ecommerce-furqon-0421113246 -o table
```

Expected output shows:

- `nsg-app` - Allows SSH (22) and HTTP (3000)
- `nsg-proxy` - Allows SSH (22), MySQL (6033), Admin (6032)
- `nsg-db` - Allows SSH (22), MySQL (3306) from proxy subnet only

### Show Firewall Effect

```bash
# Try to access DB from untrusted IP (should fail)
mysql -h 4.194.58.44 -u appuser -p -P 3306

# Access via ProxySQL (should work)
mysql -h 4.193.169.206 -u appuser -p -P 6033
```

---

## Demo 2: SQL Backup

### Run Backup Manually

```bash
# SSH to master DB
ssh azureuser@4.194.58.44

# Run backup script
sudo /opt/mysql-backup/mysql-backup.sh

# Or manually
sudo mysqldump -uroot --single-transaction --quick --routines --triggers ecommerce | gzip | sudo tee /var/backups/mysql/ecommerce_$(date +%F).sql.gz > /dev/null
```

### Show Backup Files

```bash
# List backup files
ls -la /var/backups/mysql/

# Show file size
ls -lh /var/backups/mysql/
```

Expected:

```
-rw-r--r-- 1 root root 2.4K Apr 22 10:00 ecommerce_2026-04-22.sql.gz
```

### Show Backup Content

```bash
# View backup file (gzipped)
zcat /var/backups/mysql/ecommerce_*.sql.gz | head -30
```

Expected shows: `CREATE DATABASE`, `CREATE TABLE`, `INSERT INTO` statements

---

## Demo 3: Access Rights (Master vs Slave)

### On Master DB

```bash
ssh azureuser@4.194.58.44

# Login as root
sudo mysql -uroot

# Check users
mysql> SELECT user, host, plugin FROM mysql.user WHERE user IN ('appuser', 'repl_user', 'monitor_user');
```

Expected:

```
+---------------+-----------+-----------------------+
| user          | host      | plugin                |
+---------------+-----------+-----------------------+
| appuser       | 10.0.2.% | caching_sha2_password |
| repl_user     | 10.0.3.% | caching_sha2_password |
| monitor_user  | 10.0.2.% | caching_sha2_password |
+---------------+-----------+-----------------------+
```

### Show Privileges

```bash
# On master
sudo mysql -uroot -e "SHOW GRANTS FOR 'appuser'@'10.0.2.%';"
```

Expected:

```
+------------------------------------------------------------------+
| Grants for appuser@10.0.2.%                                        |
+------------------------------------------------------------------+
| GRANT SELECT, INSERT, UPDATE ON ecommerce.* TO 'appuser'@'10.0.2.%'  |
+------------------------------------------------------------------+
```

### On Slave - Different Access

```bash
# SSH to slave (via jump)
ssh -J azureuser@4.194.58.44 azureuser@10.0.3.4

# Try INSERT (should fail - read only)
sudo mysql -uroot -e "INSERT INTO ecommerce.products (name, price, stock) VALUES ('Test', 100, 1);"
```

Expected error:

```
ERROR 1290 (HY000): The MySQL server is running with the --read-only option
```

### Show Slave is Read-Only

```bash
# On slave
sudo mysql -uroot -e "SHOW VARIABLES LIKE 'read_only';"
sudo mysql -uroot -e "SHOW VARIABLES LIKE 'super_read_only';"
```

Expected:

```
+---------------+-------+
| Variable_name | Value |
+---------------+-------+
| read_only    | ON   |
| super_read_only | ON |
+---------------+-------+
```

### Compare Settings

```bash
# Master
sudo mysql -uroot -e "SHOW VARIABLES LIKE 'read_only';"

# Slave
# (should show ON)
```

---

## Demo 4: Cron Job

### Show Scheduled Cron

```bash
# SSH to master
ssh azureuser@4.194.58.44

# List cron jobs
sudo crontab -l
```

Expected:

```
0 2 * * * /opt/mysql-backup/mysql-backup.sh >> /var/log/mysql-backup.log 2>&1
```

This means: Every day at 2:00 AM, run backup

### Show Cron Script

```bash
# View backup script
cat /opt/mysql-backup/mysql-backup.sh
```

Expected content shows:

- Creates backup in `/var/backups/mysql/`
- Deletes backups older than 7 days

### Show Log

```bash
# Check backup log
cat /var/log/mysql-backup.log
```

Expected shows backup timestamp and file size

---

## Demo 5: MySQL Replication Status

### Show Master Status

```bash
ssh azureuser@4.194.58.44
sudo mysql -uroot -e "SHOW MASTER STATUS;"
```

Expected:

```
+------------------+----------+--------------+------------------+
| File             | Position | Binlog_Do_DB   | Binlog_Ignore_DB |
+------------------+----------+--------------+------------------+
| mysql-bin.000003 |     1234 | ecommerce     |                  |
+------------------+----------+--------------+------------------+
```

### Show Slave Status

```bash
# SSH to slave
ssh -J azureuser@4.194.58.44 azureuser@10.0.3.4

sudo mysql -uroot -e "SHOW REPLICA STATUS\G"
```

Expected:

```
Replica_IO_Running: Yes
Replica_SQL_Running: Yes
```

---

## Demo 6: ProxySQL Read/Write Split

### Show ProxySQL Backends

```bash
# SSH to proxy
ssh azureuser@4.193.169.206

mysql -uadmin -padmin -h127.0.0.1 -P6032 --protocol=tcp -e "SELECT hostgroup_id, hostname, port, status FROM mysql_servers;"
```

Expected:

```
+-------------+------------+------+--------+
| hostgroup_id | hostname   | port | status |
+-------------+------------+------+--------+
| 10          | 10.0.3.5  | 3306 | ONLINE |  (Writer - Master)
| 20          | 10.0.3.4  | 3306 | ONLINE |  (Reader - Slave)
+-------------+------------+------+--------+
```

---

## Pre-Demo Checklist

Before your revision demo, verify these are working:

- [ ] All 3 VMs are running
- [ ] SSH access works for all VMs
- [ ] MySQL replication: both IO and SQL running
- [ ] Backup files exist in `/var/backups/mysql/`
- [ ] Cron job is scheduled (`crontab -l`)
- [ ] ProxySQL has both backends registered

## Quick Verification Commands

Run these before your demo:

```bash
# 1. Check VMs
az vm list --resource-group rg-ecommerce-devops -o table

# 2. Check replication
ssh azureuser@4.194.58.44 "sudo mysql -uroot -e 'SHOW REPLICA STATUS\G'" | grep Running

# 3. Check backups
ssh azureuser@4.194.58.44 "ls -la /var/backups/mysql/"

# 4. Check cron
ssh azureuser@4.194.58.44 "sudo crontab -l"
```

---

## Presentation Flow

1. **Introduction** - Show architecture diagram
2. **Security** - Show NSG rules (Demo 1)
3. **Backup** - Show manual backup + cron job (Demo 2, 4, 5)
4. **Access Rights** - Compare master vs slave (Demo 3)
5. **Replication** - Show status (Demo 5, 6)
6. **Q&A** - Answer questions
