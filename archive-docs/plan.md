# Goal
Deliver an MVP customer-facing VPS product (separate from the existing admin app) that provisions VPS containers on a pool of VDS hosts running `hardware-controller`, using a shared PostgreSQL database. After each phase, the product is deployable and testable end-to-end, even if many features are still missing.
# Current state (what exists today)
The repo already contains:
* `hardware-controller/`: Flask API that can create/manage LXD containers and assign/release public IPv4 via iptables + netplan.
* `hardware-admin/`: Next.js admin UI that stores hardware entries locally (SQLite via Prisma) and proxies requests to each hardware-controller.
* Host-level scripts (e.g. `setup-vds.sh`) to bootstrap a VDS and deploy the controller.
# Target MVP architecture
* Customer-facing app: new Next.js project (UI + API routes) acting as the control plane.
* Admin app: continues to exist, but is updated to use the shared PostgreSQL DB and manage tiers, hardware, and IP pools.
* Shared DB: PostgreSQL (docker-compose) with Prisma schemas shared (or kept in sync) across both apps.
# Phases
## Phase 0 — Repo + DB foundation ("platform")
Scope
* Add a top-level `docker-compose.yml` that starts PostgreSQL with a persistent volume.
* Define the shared database schema (Prisma) for:
    * hardware servers
    * IP inventory per hardware
    * VPS tiers
    * customers
    * VPS instances
    * billing transactions
    * alerts
* Decide how to share schema:
    * Option A: create a `packages/db/` (recommended) that both apps import.
    * Option B: duplicate schemas and enforce migration discipline.
* Add migration workflow and seed scripts (admin user + initial tiers optional).
Test gate
* `docker compose up` brings up PostgreSQL.
* Migrations apply cleanly on a fresh DB.
* Seed creates an admin account and verifies DB connectivity from both apps.
Deliverable
* A single shared database that both applications can connect to locally.
## Phase 1 — Admin app becomes the “inventory system” (wheels)
Scope (admin-only; no customer app yet)
* Move `hardware-admin` from SQLite to PostgreSQL.
* Implement these admin features against the shared DB:
    * Hardware CRUD (name, controller IP, controller API key, total resources).
    * Per-hardware IP pool management (single IP add, bulk range add, list, status).
    * Tier management (CRUD + activate/deactivate + ordering).
    * Alerts view (read + acknowledge).
* Implement background health polling in admin:
    * Periodically call each hardware-controller `/health` and `/info`.
    * Update hardware status (online/offline) and update computed capacity in DB.
* IP outage alerting:
    * If available IP count for a hardware drops below threshold, create alert.
Test gate
* Add a hardware entry pointing to a real controller; admin can view live `/info`.
* Add IPs to a hardware’s IP pool; statuses persist in DB.
* Create/edit tiers; active tiers show up correctly.
* Simulate IP shortage: alert appears and can be acknowledged.
Deliverable
* Admin app is now the source of truth for hardware capacity, tiers, and IP inventory.
## Phase 2 — Customer app scaffold + auth + credits (chassis)
Scope
* Create a new Next.js project for the customer-facing dashboard (separate deployable).
* Implement customer auth:
    * Register/login/logout
    * JWT session cookies
* Implement credits MVP:
    * “Top up $50” button that immediately credits the user (no Stripe yet)
    * Transaction history page
* Customer dashboard shell:
    * Show credit balance
    * Empty VPS state
Test gate
* Customer can register and login.
* Customer can top up $50 and see balance + transaction record.
Deliverable
* A usable customer portal with authentication and credits.
## Phase 3 — Provisioning control plane (engine, but minimal)
Scope
* Implement orchestration API routes in the customer app:
    * List tiers and compute availability per tier.
    * Create VPS:
        * Select tier + OS + name + root password
        * Pick hardware that is online and has capacity
        * Allocate the next available public IP for that hardware (DB transaction)
        * Call hardware-controller to create container
        * Assign IP via hardware-controller
        * Persist VPS instance record (container name, IPs, status)
    * Start/stop/restart/delete VPS
* Tier availability logic:
    * A tier is disabled if no online hardware can satisfy (cpu, ram, disk) or if there’s no available IP on that hardware.
    * Availability is computed dynamically from DB + cached health data.
* Error handling:
    * If container creation succeeds but IP assignment fails, mark VPS as error and emit admin alert.
    * If DB allocation happens but controller call fails, roll back allocation and release IP.
Test gate
* With 1 online hardware and a few available IPs:
    * Customer can create a VPS successfully.
    * Customer can see VPS with public IP and status.
    * Customer can start/stop/restart.
    * Customer can delete VPS and IP returns to available pool.
* If hardware has insufficient RAM for a tier, that tier shows disabled for the customer.
Deliverable
* End-to-end VPS provisioning from customer UI.
## Phase 4 — Web console (driver controls)
Scope
* Implement a web terminal in the customer app:
    * VPS detail page has “Console”
    * Terminal uses xterm.js in the browser
    * Backend provides a WebSocket endpoint
    * The WebSocket proxies to the chosen hardware server and attaches to the container shell
* Security
    * Only the VPS owner can open console
    * Short-lived console token (minutes)
    * Rate limit console sessions per user
Test gate
* Customer can open console and run shell commands.
* Disconnect/reconnect works.
* Unauthorized access is blocked.
Deliverable
* Customer can manage VPS via web console without SSH.
## Phase 5 — Billing cron + enforcement + polish (roadworthy)
Scope
* Implement hourly billing job:
    * Charge running VPS instances based on tier hourly_rate
    * Write transaction records
    * Update balances
    * Ensure idempotency (no double-charge)
* Enforcement
    * If credits are exhausted:
        * Stop VPS
        * Mark VPS status accordingly
        * Create customer-visible notification and admin alert
* Basic abuse controls
    * API rate limiting
    * VPS creation limits per account (configurable)
Test gate
* Simulate time passing:
    * Running VPS gets charged correctly
    * Low balance triggers stop and records event
    * Restart is blocked until credits are positive (or allowed but immediately billed, depending on policy)
Deliverable
* MVP can run continuously with basic billing enforcement.
# Phase 2+ explicitly deferred (out of MVP)
* Snapshots/backups
* Resize
* SSH key management
* Firewall management
* Private networking / VPC
* Real Stripe integration
* Managed services (S3, DBaaS, registry)
