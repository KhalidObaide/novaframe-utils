# Quick Test Guide - Phase 0 & 1

## 🚀 Start Everything

```bash
# 1. Start PostgreSQL
docker compose up -d

# 2. Check it's running
docker ps | grep redcloud

# 3. Seed database
cd packages/db
npm run db:seed

# 4. Start admin dashboard
cd ../hardware-admin
npm run dev
```

## 🔑 Login

- URL: `http://localhost:3000/login`
- Username: `admin`
- Password: `admin123`

## ✅ Quick API Tests

### Add Hardware
```bash
curl -X POST http://localhost:3000/api/hardware \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test-VDS",
    "ipAddress": "85.190.254.209",
    "apiKey": "your-api-key"
  }'
```

### Add IP Range
```bash
curl -X POST http://localhost:3000/api/hardware/1/ips \
  -H "Content-Type: application/json" \
  -d '{"ipRange": "192.168.1.10-20"}'
```

### Create Tier
```bash
curl -X POST http://localhost:3000/api/tiers \
  -H "Content-Type: application/json" \
  -d '{
    "name": "XLarge",
    "cpuCores": 8,
    "memoryGb": 16,
    "diskGb": 200,
    "monthlyRate": 80
  }'
```

### Health Poll
```bash
curl -X POST http://localhost:3000/api/health-poll
```

### View Alerts
```bash
curl http://localhost:3000/api/alerts?unacknowledged=true
```

## 📊 Database Browser

```bash
cd packages/db
npm run db:studio
```

Opens Prisma Studio at: `http://localhost:5555`

## 🐛 Troubleshooting

**Database won't start:**
```bash
docker compose restart postgres
```

**Can't login:**
```bash
cd packages/db && npm run db:seed
```

**Prisma errors:**
```bash
cd packages/db && npm run db:generate
```

## 📖 Full Documentation

- `TESTING-PHASE-1.md` — Complete testing guide
- `PHASE-0-1-SUMMARY.md` — Implementation summary
- `SRS-MVP.md` — Full requirements
