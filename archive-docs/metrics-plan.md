# Container Metrics — Collection, Storage & Visualization
## Problem
Currently, there is no visibility into container resource usage (CPU, memory, disk, network). Customers and admins have no way to see how their VPS instances are performing over time.
## Current Architecture (relevant)
* **hardware-controller** (Python/Flask, per-VDS host): manages LXD containers, exposes REST API. Already has background services (`snapshot_scheduler`, etc.).
* **customer-portal** (Next.js + Prisma + PostgreSQL): web app, uses `HardwareClient` to proxy calls to hardware controllers. Cron jobs via external service (cron-job.org) calling API routes (billing, health-poll).
* LXD natively provides per-container state via `lxc query /1.0/instances/<name>/state` (CPU ns, memory bytes, disk bytes, network counters, process count).
## Design Decisions
**Metrics source:** `lxc query /1.0/instances/<name>/state` per container — returns structured JSON with CPU, memory, disk, network stats. Simpler than parsing `/1.0/metrics` Prometheus format and filters to only our managed containers.
**Storage:** Regular PostgreSQL table with composite index on `(vps_instance_id, time)`. This avoids the complexity of installing TimescaleDB on the Docker Postgres and works seamlessly with Prisma. If scale demands it later, we can swap the table to a TimescaleDB hypertable with zero code changes (just a `SELECT create_hypertable(...)` migration). A cron-triggered cleanup removes records older than 30 days.
**Collection pattern:** Same as existing health-poll/billing — an external cron hits `POST /api/metrics/collect` every 60 seconds. This endpoint loops through online hardware servers, calls a new bulk metrics endpoint, and inserts into PostgreSQL.
**Charting:** `recharts` — lightweight, React-native, no heavy dependencies.
## Phase 1: Hardware Controller — Metrics Endpoint
Add a new service `services/metrics.py` and a single new route to `app.py`.
### New file: `hardware-controller/services/metrics.py`
* Function `get_container_metrics(container_name)` → calls `lxc query /1.0/instances/{name}/state`, returns dict:
    * `cpu_usage_ns` (int) — cumulative CPU nanoseconds
    * `memory_used_bytes` (int)
    * `memory_limit_bytes` (int) — from container config `limits.memory`
    * `disk_used_bytes` (int) — root device usage
    * `disk_limit_bytes` (int) — root device size from config
    * `network_rx_bytes` (int)
    * `network_tx_bytes` (int)
    * `process_count` (int)
* Function `get_all_metrics()` → loops through all running containers, returns list of `{container_name, ...metrics}`
### New route in `app.py`
* `GET /metrics/containers` (auth required) — calls `get_all_metrics()`, returns JSON.
* `GET /container/<name>/metrics` (auth required) — single container live metrics.
## Phase 2: Customer Portal — Database & Collection
### Prisma Schema
New model `ContainerMetric` in `schema.prisma`:
```warp-runnable-command
model ContainerMetric {
  id              BigInt   @id @default(autoincrement())
  time            DateTime @default(now())
  vpsInstanceId   String   @map("vps_instance_id")
  cpuUsageNs      BigInt   @map("cpu_usage_ns")         // cumulative CPU nanoseconds
  memoryUsedBytes BigInt   @map("memory_used_bytes")
  memoryLimitBytes BigInt  @map("memory_limit_bytes")
  diskUsedBytes   BigInt   @map("disk_used_bytes")
  diskLimitBytes  BigInt   @map("disk_limit_bytes")
  networkRxBytes  BigInt   @map("network_rx_bytes")
  networkTxBytes  BigInt   @map("network_tx_bytes")
  processCount    Int      @map("process_count")
  @@index([vpsInstanceId, time])
  @@index([time])
  @@map("container_metrics")
}
```
### HardwareClient
Add two methods to `hardware-client.ts`:
* `getContainerMetrics(name)` → `GET /container/{name}/metrics`
* `getAllContainerMetrics()` → `GET /metrics/containers`
### Collection Cron Route
New API route: `POST /api/metrics/collect`
* Protected by `CRON_SECRET` (same as billing/run)
* Fetches all online hardware servers from DB
* For each: calls `getAllContainerMetrics()` via HardwareClient
* Maps `container_name` → `vpsInstanceId` using VpsInstance table
* Bulk inserts into `container_metrics`
* Deletes records older than 30 days (retention cleanup)
* Called by external cron every 60 seconds
## Phase 3: Customer Portal — Query API
New API route: `GET /api/vps/[id]/metrics`
Query params:
* `period` — `1h`, `6h`, `24h`, `7d`, `30d` (default: `24h`)
* Returns time-series data points downsampled appropriately:
    * 1h/6h → raw points (1/min)
    * 24h → 5-min averages
    * 7d → 30-min averages
    * 30d → 2-hour averages
* Response shape:
```json
{
  "points": [
    {
      "time": "2026-03-12T10:00:00Z",
      "cpuPercent": 12.5,
      "memoryUsedMb": 512,
      "memoryLimitMb": 1024,
      "memoryPercent": 50.0,
      "diskUsedGb": 5.2,
      "diskLimitGb": 20,
      "diskPercent": 26.0,
      "networkRxMb": 150.3,
      "networkTxMb": 45.1,
      "processCount": 42
    }
  ],
  "period": "24h"
}
```
* CPU percent is computed from the delta of consecutive `cpu_usage_ns` values divided by elapsed wall time × CPU count.
* Auth: requires session, verifies VPS ownership.
## Phase 4: Frontend — Metrics Tab
Add a **"Metrics"** tab to the VPS detail page (`vps/[id]/page.tsx`).
### Dependencies
* `recharts` — add to package.json
### UI Components
* Time range selector buttons: 1h, 6h, 24h, 7d, 30d
* **CPU Usage** — area chart (0–100%)
* **Memory Usage** — area chart showing used vs limit, with percentage
* **Disk Usage** — area chart or single bar showing used/total
* **Network I/O** — dual-line chart (RX in blue, TX in green, in MB)
* Current snapshot card at the top (latest values in bold)
* Auto-refresh every 60 seconds when viewing 1h or 6h range
### Tab Placement
Add `'metrics'` to the tab list (between 'overview' and 'connect'), shown only when VPS status is `running` or `stopped`.
## File Changes Summary
**hardware-controller (new/modified):**
* `services/metrics.py` (new) — LXD state query + parsing
* `services/__init__.py` (modified) — import metrics
* `app.py` (modified) — 2 new routes
**customer-portal (new/modified):**
* `prisma/schema.prisma` (modified) — add ContainerMetric model
* `prisma/migrations/…` (new) — migration
* `src/lib/hardware-client.ts` (modified) — 2 new methods
* `src/app/api/metrics/collect/route.ts` (new) — cron collection endpoint
* `src/app/api/vps/[id]/metrics/route.ts` (new) — query endpoint
* `src/app/(dashboard)/[tenantId]/vps/[id]/page.tsx` (modified) — add Metrics tab
* `package.json` (modified) — add recharts
