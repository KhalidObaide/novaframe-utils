# RedCloud - Quick Start Guide

## Phase 0: Database Setup ✅ COMPLETE

### 1. Start PostgreSQL

```bash
# From repo root
docker compose up -d
```

### 2. Setup Database Package

```bash
cd packages/db
npm install
cp .env.example .env
npm run db:generate
npm run db:push
npm run db:seed
```

### 3. Verify Setup

```bash
# Check PostgreSQL is running
docker ps | grep redcloud-postgres

# Open Prisma Studio to view database
npm run db:studio
```

### Default Credentials

**Database:**
- Host: `localhost:5432`
- User: `postgres`
- Password: `postgres`
- Database: `redcloud`

**Admin User:**
- Username: `admin`
- Password: `admin123`

**Default Tiers Seeded:**
- Nano: 1 CPU, 1GB RAM, $5/mo
- Small: 1 CPU, 2GB RAM, $10/mo
- Medium: 2 CPU, 4GB RAM, $20/mo
- Large: 4 CPU, 8GB RAM, $40/mo

## Next Steps

### Phase 1: Update Admin App (IN PROGRESS)

The admin dashboard needs to be updated to use the shared PostgreSQL database and implement:
- Hardware server management
- IP pool management per hardware
- VPS tier management
- System alerts
- Health polling

See `SRS-MVP.md` and the implementation plan for details.

## Useful Commands

### Database

```bash
cd packages/db

# Generate Prisma client
npm run db:generate

# Push schema changes
npm run db:push

# Create migration
npm run db:migrate

# Re-seed database
npm run db:seed

# Open Prisma Studio GUI
npm run db:studio
```

### Docker

```bash
# Start PostgreSQL
docker compose up -d

# Stop PostgreSQL
docker compose down

# Reset database (⚠️ destroys all data)
docker compose down -v && docker compose up -d
```

## Project Structure

```
RedCloud/
├── docker-compose.yml          # PostgreSQL container
├── packages/
│   └── db/                     # Shared database package
│       ├── schema.prisma       # Database schema
│       ├── seed.js            # Seed data script
│       └── index.js           # Prisma client export
├── hardware-admin/            # Admin dashboard (to be updated)
├── hardware-controller/       # VDS controller API (existing)
├── SRS-MVP.md                # Requirements document
└── QUICKSTART.md             # This file
```

## Troubleshooting

### PostgreSQL won't start
```bash
# Check logs
docker logs redcloud-postgres

# Restart
docker compose restart postgres
```

### Database connection errors
```bash
# Verify connection
docker exec redcloud-postgres psql -U postgres -d redcloud -c "SELECT version();"
```

### Reset everything
```bash
# Stop and remove volumes
docker compose down -v

# Start fresh
docker compose up -d
cd packages/db
npm run db:push
npm run db:seed
```
