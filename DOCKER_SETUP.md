# Docker Setup Guide for Dograh AI

## ✅ Setup Complete!

Your Dograh AI platform is now running successfully with Docker!

## 🚀 Quick Access

- **Main Application**: http://localhost:3010
- **API Health Check**: http://localhost:8000/api/v1/health
- **MinIO Console**: http://localhost:9001 (admin/minioadmin)
- **Cloudflare Tunnel Metrics**: http://localhost:2000/metrics

## 📋 Services Running

| Service | Status | Port | Description |
|---------|--------|------|-------------|
| **UI** | ✅ Running | 3010 | Next.js Frontend |
| **API** | ✅ Running | 8000 | Python FastAPI Backend |
| **PostgreSQL** | ✅ Running | 5432 | Database |
| **Redis** | ✅ Running | 6379 | Cache & Message Queue |
| **MinIO** | ✅ Running | 9000/9001 | S3-compatible Storage |
| **Cloudflared** | ✅ Running | 2000 | Tunnel for external access |

## 🎯 What's Next?

1. **Open the Application**: Visit http://localhost:3010
2. **Create Your First Voice Bot**:
   - Choose **Inbound** or **Outbound** calling
   - Name your bot (e.g., "Lead Qualification")
   - Describe the use case in 5-10 words
   - Click **Web Call** to test it

## 🔧 Management Commands

### Start Services
```powershell
docker compose up -d
```

### Stop Services
```powershell
docker compose down
```

### View Logs
```powershell
docker compose logs -f
```

### Check Status
```powershell
docker compose ps
```

### Restart a Service
```powershell
docker compose restart [service-name]
# Example: docker compose restart ui
```

## 🗂️ Volume Data

Persistent data is stored in Docker volumes:
- `postgres_data`: Database files
- `redis_data`: Redis persistence
- `minio-data`: File storage
- `shared-tmp`: Temporary files

## 🔑 Default Credentials

- **PostgreSQL**: postgres/postgres
- **Redis**: password: redissecret
- **MinIO**: minioadmin/minioadmin

## 🛠️ Environment Variables

Current configuration:
- `REGISTRY=ghcr.io/dograh-hq`
- `ENABLE_TELEMETRY=true`

## 📚 Additional Resources

- [Project Documentation](https://docs.dograh.com)
- [GitHub Repository](https://github.com/dograh-hq/dograh)
- [Slack Community](https://join.slack.com/t/dograh-community/shared_invite/zt-3czr47sw5-MSg1J0kJ7IMPOCHF~03auQ)

---

**Note**: First startup may take 2-3 minutes to download all images. All services are now healthy and ready for use!