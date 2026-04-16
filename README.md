# Mini Project Stage 1: Containerization

## Overview

This stage involves containerizing a simple e-commerce web application using Docker and scanning the image for vulnerabilities using Trivy (Docker Scout alternative).

## Project Structure

```
mini-project2/
├── src/
│   └── index.js          # Express.js application
├── package.json          # Node.js dependencies
├── Dockerfile            # Multi-stage Docker build
├── .dockerignore         # Excludes files from build
├── .env.example          # Environment variables template
└── README.md             # This file
```

## Prerequisites

- Docker installed and running
- Trivy installed for vulnerability scanning:
  ```bash
  # macOS
  brew install trivy
  
  # Linux
  sudo apt-get install trivy
  
  # Or download from https://github.com/aquasecurity/trivy/releases
  ```

## Step-by-Step Instructions

### Step 1: Install Dependencies

```bash
npm install
```

### Step 2: Build Docker Image

```bash
docker build -t ecommerce-app:1.0.0 .
```

### Step 3: Run the Container

```bash
# Run in detached mode
docker run -d -p 3000:3000 --name ecommerce-app-test ecommerce-app:1.0.0

# Check if running
docker ps

# View logs
docker logs -f ecommerce-app-test
```

### Step 4: Test the Application

```bash
# Health check endpoint
curl http://localhost:3000/health

# Expected response:
# {"status":"healthy","timestamp":"2026-..."}
```

### Step 5: Vulnerability Scanning

Scan the built image for HIGH and CRITICAL vulnerabilities:

```bash
trivy image --severity HIGH,CRITICAL ecommerce-app:1.0.0
```

Expected result after fixes: **0 vulnerabilities** on OS layer

### Step 6: Clean Up

```bash
# Stop and remove container
docker stop ecommerce-app-test && docker rm ecommerce-app-test
```

## Application Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check (no DB required) |
| GET | `/api/products` | List products (READ query) |
| POST | `/api/orders` | Create order (WRITE query) |
| GET | `/api/orders` | List orders (READ query) |

## Environment Variables

Create a `.env` file based on `.env.example`:

```env
PORT=3000
DB_HOST=proxysql
DB_PORT=3306
DB_USER=appuser
DB_PASSWORD=apppassword
DB_NAME=ecommerce
```

## Dockerfile Features

- **Multi-stage build**: Reduces final image size
- **Alpine base image**: Minimal OS footprint (~170MB vs ~900MB)
- **Non-root user**: Runs as `nodejs` (uid 1001) for security
- **Health check**: Built-in container health monitoring
- **Layer caching**: Optimized for rebuild speed

## Troubleshooting

### Container exits immediately

```bash
# Check logs
docker logs ecommerce-app-test

# Run interactively to debug
docker run -it ecommerce-app:1.0.0 /bin/sh
```

### Port already in use

```bash
# Check what's using port 3000
lsof -i :3000

# Or use a different port
docker run -d -p 3001:3000 ecommerce-app:1.0.0
```

### Database connection fails

This is expected if ProxySQL/MySQL is not running. The application handles this gracefully and returns appropriate error messages.

## Scanning Results Interpretation

### Before Fix (Node 18 Alpine)
- 11 OS vulnerabilities (libcrypto3, libssl3, musl, zlib)
- Multiple HIGH/CRITICAL CVEs

### After Fix (Node 22 Alpine)
- 0 OS vulnerabilities
- Alpine 3.23.4 with patched OpenSSL

## Next Stages

This application is designed to connect to:
- **Stage 2**: Terraform → Azure VMs (ProxySQL, MySQL Master/Slave, App)
- **Stage 3**: Ansible → Configure replication, SSL/TLS, backups

---

For questions, refer to the main project documentation.# devops-miniproject2
