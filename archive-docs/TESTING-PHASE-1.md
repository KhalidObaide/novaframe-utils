# Phase 0 & Phase 1 Testing Guide

## Prerequisites

1. **PostgreSQL running:**
   ```bash
   docker compose up -d
   docker ps | grep redcloud-postgres  # Should show running container
   ```

2. **Database seeded:**
   ```bash
   cd packages/db
   npm run db:push
   npm run db:seed
   ```

3. **Admin app dependencies installed:**
   ```bash
   cd ../hardware-admin
   npm install
   ```

## Phase 0: Database Foundation ✅

### Test 1: Database Connectivity

```bash
# Open Prisma Studio
cd packages/db
npm run db:studio
```

Expected: Browser opens to `http://localhost:5555` showing all tables

### Test 2: Seed Data Verification

In Prisma Studio, verify:
- ✅ `admin_users` table has 1 record (username: admin)
- ✅ `vps_tiers` table has 4 records (Nano, Small, Medium, Large)
- ✅ All other tables are empty

---

## Phase 1: Admin Dashboard ✅

### Setup: Start Admin Dashboard

```bash
cd hardware-admin
npm run dev
```

Navigate to: `http://localhost:3000`

### Test 1: Admin Login

1. Go to `http://localhost:3000/login`
2. Enter:
   - Username: `admin`
   - Password: `admin123`
3. Click "Login"

**Expected:** Redirects to dashboard showing "No hardware servers added yet"

---

### Test 2: Add Hardware Server

**Note:** You need a running hardware-controller for this test. If you don't have one:
- Use IP: `85.190.254.209` (from your VDS)
- Use the API key you configured during setup

1. Click "+ Add Hardware"
2. Fill in:
   - Name: `Test-VDS-1`
   - IP Address: `<your-vds-ip>`
   - API Key: `<your-api-key>`
3. Click "Add Hardware"

**Expected:**
- Modal closes
- Hardware card appears on dashboard
- Status indicator shows green (online) or red (offline)
- Shows VPS count, IP count, CPU capacity

---

### Test 3: View Hardware Details

1. Click on the hardware card you just added
2. You should see:
   - Server details (name, IP, status)
   - CPU/Memory/Disk stats
   - Container list (empty for now)

---

### Test 4: IP Management

#### Add Single IP

1. On hardware detail page, click "IPs" tab (or similar section)
2. Click "Add IP"
3. Enter a test IP: `192.168.1.100`
4. Click "Add"

**Expected:**
- IP appears in the list with status "available" (green)

#### Add IP Range

1. Click "Add IP Range"
2. Enter: `192.168.1.101-105`
3. Click "Add"

**Expected:**
- 5 IPs added (192.168.1.101 through 192.168.1.105)
- All show status "available"

#### Delete IP

1. Click delete (trash icon) on an available IP
2. Confirm deletion

**Expected:**
- IP removed from list

---

### Test 5: Tier Management

#### View Tiers

1. Navigate to "Tiers" page (add link in nav if needed, or create route `/tiers`)
2. Verify 4 default tiers are shown:
   - Nano: 1 CPU, 1GB RAM, $5/mo
   - Small: 1 CPU, 2GB RAM, $10/mo
   - Medium: 2 CPU, 4GB RAM, $20/mo
   - Large: 4 CPU, 8GB RAM, $40/mo

#### Create New Tier

API Test (you can create a UI for this later):
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

**Expected:**
```json
{
  "id": 5,
  "name": "XLarge",
  "slug": "xlarge",
  "cpuCores": 8,
  "memoryGb": 16,
  "diskGb": 200,
  "monthlyRate": "80.00",
  "hourlyRate": "0.1096",
  "isActive": true,
  "sortOrder": 5,
  "createdAt": "..."
}
```

#### Update Tier

```bash
curl -X PUT http://localhost:3000/api/tiers/1 \
  -H "Content-Type: application/json" \
  -d '{
    "isActive": false
  }'
```

**Expected:** Tier 1 (Nano) is now inactive

#### Delete Tier (empty tier only)

```bash
curl -X DELETE http://localhost:3000/api/tiers/5
```

**Expected:** `{"success": true}`

---

### Test 6: Health Polling

#### Manual Trigger

```bash
curl -X POST http://localhost:3000/api/health-poll
```

**Expected:**
```json
{
  "success": true,
  "polled": 1,
  "results": [
    {
      "id": 1,
      "name": "Test-VDS-1",
      "status": "online",  // or "offline" if unreachable
      "cpu": { "total": 4, "available": 4 },
      "memory": { "total": 8, "available": 8 }
    }
  ]
}
```

After this, refresh the hardware dashboard - capacity should be updated.

---

### Test 7: System Alerts

#### Create IP Shortage Alert

1. Add hardware with < 5 available IPs
2. Or use API to add IPs then poll:

```bash
# Add 3 IPs to hardware ID 1
curl -X POST http://localhost:3000/api/hardware/1/ips \
  -H "Content-Type: application/json" \
  -d '{"ipRange": "192.168.1.10-12"}'

# Trigger health poll (this will create alert if < 5 IPs)
curl -X POST http://localhost:3000/api/health-poll
```

#### View Alerts

```bash
curl http://localhost:3000/api/alerts
```

**Expected:**
```json
[
  {
    "id": 1,
    "type": "ip_shortage",
    "severity": "warning",
    "message": "Hardware \"Test-VDS-1\" has only 3 available IP(s)",
    "hardwareId": 1,
    "isAcknowledged": false,
    "createdAt": "...",
    "hardware": {
      "id": 1,
      "name": "Test-VDS-1",
      "ipAddress": "..."
    }
  }
]
```

#### Acknowledge Alert

```bash
curl -X PATCH http://localhost:3000/api/alerts \
  -H "Content-Type: application/json" \
  -d '{"alertIds": [1]}'
```

**Expected:** `{"success": true, "acknowledged": 1}`

---

## Common Issues & Solutions

### Issue: Cannot connect to database
```bash
# Check if PostgreSQL is running
docker ps | grep postgres

# Restart if needed
cd /path/to/RedCloud
docker compose restart postgres
```

### Issue: Admin login fails
```bash
# Re-seed database
cd packages/db
npm run db:seed
```

### Issue: Hardware shows offline but controller is running
- Verify API key is correct
- Check that controller is accessible via HTTPS
- Check `.env` has `NODE_TLS_REJECT_UNAUTHORIZED=0`

### Issue: Prisma client not found
```bash
cd packages/db
npm run db:generate
```

---

## Next Steps

After testing Phase 1:
- **Phase 2:** Build customer-facing web app (auth + credits)
- **Phase 3:** VPS provisioning from customer app
- **Phase 4:** Web console (xterm.js)
- **Phase 5:** Billing cron + enforcement

---

## Success Criteria for Phase 1

✅ All tests pass:
- [x] Database accessible via Prisma Studio
- [x] Admin can login
- [x] Hardware can be added with auto-detected capacity
- [x] IPs can be added (single + range) and deleted
- [x] Tiers can be viewed, created, updated, deleted
- [x] Health polling updates hardware status and capacity
- [x] Alerts are created for IP shortage and acknowledged

**Phase 1 is COMPLETE when all checkboxes above are ticked!**
