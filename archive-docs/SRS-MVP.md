# RedCloud VPS Platform - Software Requirements Specification (MVP)

**Version:** 1.0  
**Date:** March 2, 2026  
**Project:** RedCloud - Customer-Facing VPS Platform

---

## 1. Executive Summary

RedCloud is a cloud hosting platform that provides Virtual Private Servers (VPS) to end customers. The MVP focuses on delivering a fully functional VPS provisioning and management system with a customer-facing web application, administrative controls, and automated orchestration across multiple hardware servers.

---

## 2. System Architecture

### 2.1 Components

```
┌──────────────────────────────────────────────────────────────┐
│  Customer Web App (NEW - Next.js + API Routes)               │
│  - Public-facing UI for customers                            │
│  - Authentication & authorization                            │
│  - VPS management interface                                  │
│  - Web-based SSH console (xterm.js)                          │
│  - Credit management                                         │
│  - API routes handle orchestration logic                     │
└────────────────────┬─────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────────┐
│  PostgreSQL Database (Shared)                                │
│  - Stores all system data                                    │
│  - Accessed by both Customer App and Admin Dashboard         │
└────────────────────┬─────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────────┐
│  Admin Dashboard (EXISTING - Enhanced)                       │
│  - Manage hardware pool                                      │
│  - Manage IP inventory                                       │
│  - Define VPS pricing tiers                                  │
│  - Monitor system health & alerts                            │
│  - View all customer VPS instances                           │
└──────────────────────────────────────────────────────────────┘
                     │
                     │ (orchestrates via HTTPS API)
                     │
                     ▼
┌──────────────────────────────────────────────────────────────┐
│  Hardware Controllers (EXISTING)                             │
│  - Multiple VDS servers running hardware-controller          │
│  - Each exposes REST API for container management            │
│  - LXD + iptables NAT for isolation                          │
└──────────────────────────────────────────────────────────────┘
```

### 2.2 Technology Stack

- **Customer Web App:** Next.js 14+ (React, Server Components, API Routes)
- **Admin Dashboard:** Next.js 14+ (existing, enhanced)
- **Database:** PostgreSQL 15+ (Docker container)
- **ORM:** Prisma
- **Authentication:** JWT (jose library)
- **Web Console:** xterm.js + WebSocket
- **Container Runtime:** LXD (existing on hardware controllers)
- **Reverse Proxy:** nginx (existing on hardware controllers)

---

## 3. Database Schema

### 3.1 Core Tables

#### `customers`
- `id` - UUID, primary key
- `email` - string, unique, indexed
- `password` - string (bcrypt hashed)
- `name` - string
- `credits` - decimal (default 0.00)
- `created_at` - timestamp
- `updated_at` - timestamp

#### `vps_instances`
- `id` - UUID, primary key
- `customer_id` - UUID, foreign key → customers
- `hardware_id` - int, foreign key → hardware_servers
- `tier_id` - int, foreign key → vps_tiers
- `name` - string (customer-defined)
- `container_name` - string (internal LXD name)
- `status` - enum: creating, running, stopped, deleting, error
- `private_ip` - string
- `public_ip` - string, nullable
- `ssh_password` - string (encrypted)
- `os_image` - string (e.g., ubuntu-24.04)
- `cpu_cores` - int
- `memory_gb` - int
- `disk_gb` - int
- `hourly_rate` - decimal
- `created_at` - timestamp
- `last_billed_at` - timestamp
- `deleted_at` - timestamp, nullable

#### `hardware_servers`
- `id` - int, primary key
- `name` - string (e.g., "VDS-Frankfurt-1")
- `ip_address` - string
- `api_key` - string (encrypted)
- `status` - enum: online, offline, maintenance
- `total_cpu` - int
- `total_memory_gb` - int
- `total_disk_gb` - int
- `available_cpu` - int
- `available_memory_gb` - int
- `available_disk_gb` - int
- `created_at` - timestamp
- `last_health_check` - timestamp

#### `ip_addresses`
- `id` - int, primary key
- `hardware_id` - int, foreign key → hardware_servers
- `ip_address` - string, unique
- `status` - enum: available, assigned, reserved
- `vps_instance_id` - UUID, foreign key → vps_instances, nullable
- `created_at` - timestamp

#### `vps_tiers`
- `id` - int, primary key
- `name` - string (e.g., "Small", "Medium", "Large")
- `slug` - string (e.g., "small", "medium", "large")
- `cpu_cores` - int
- `memory_gb` - int
- `disk_gb` - int
- `hourly_rate` - decimal (e.g., 0.007 = $5/month)
- `monthly_rate` - decimal (for display, e.g., 5.00)
- `is_active` - boolean
- `sort_order` - int
- `created_at` - timestamp

#### `billing_transactions`
- `id` - int, primary key
- `customer_id` - UUID, foreign key → customers
- `type` - enum: credit_purchase, vps_charge, refund
- `amount` - decimal
- `balance_after` - decimal
- `description` - string
- `vps_instance_id` - UUID, nullable
- `created_at` - timestamp

#### `admin_users`
- `id` - int, primary key
- `username` - string, unique
- `password` - string (bcrypt hashed)
- `created_at` - timestamp

#### `system_alerts`
- `id` - int, primary key
- `type` - enum: ip_shortage, hardware_offline, capacity_low
- `severity` - enum: info, warning, critical
- `message` - text
- `hardware_id` - int, nullable
- `is_acknowledged` - boolean
- `created_at` - timestamp
- `acknowledged_at` - timestamp, nullable

---

## 4. Functional Requirements

### 4.1 Customer Web Application

#### 4.1.1 Authentication
- **FR-1.1:** Customer registration with email and password
- **FR-1.2:** Email validation (basic format check, no verification email for MVP)
- **FR-1.3:** Customer login with JWT session
- **FR-1.4:** Logout functionality
- **FR-1.5:** Password must be at least 8 characters

#### 4.1.2 Dashboard
- **FR-2.1:** Display customer's current credit balance prominently
- **FR-2.2:** Display list of customer's VPS instances with:
  - Name
  - Status (running/stopped/creating)
  - Public IP
  - Tier (specs)
  - Monthly cost
- **FR-2.3:** Quick actions: Start, Stop, Delete VPS
- **FR-2.4:** "Create New VPS" button

#### 4.1.3 VPS Creation
- **FR-3.1:** Display available VPS tiers as cards with:
  - Tier name
  - CPU cores
  - RAM (GB)
  - Disk (GB)
  - Monthly price
  - "Select" button
- **FR-3.2:** Disable tiers that cannot be provisioned (no capacity/IPs)
- **FR-3.3:** VPS creation form:
  - VPS name (customer-defined, alphanumeric + hyphens)
  - Operating system selector (ubuntu-24.04, ubuntu-22.04, debian-12, etc.)
  - Root password field
- **FR-3.4:** Validate sufficient credits before creation
- **FR-3.5:** Orchestration logic:
  1. Find hardware with sufficient resources
  2. Allocate IP from available pool
  3. Call hardware-controller API to create container
  4. Save VPS instance in database
  5. Update hardware capacity
  6. Mark IP as assigned
- **FR-3.6:** Show creation progress (async task polling)
- **FR-3.7:** On success, display VPS details (IP, SSH command, password)

#### 4.1.4 VPS Management
- **FR-4.1:** VPS detail page showing:
  - Status indicator
  - Public IP address
  - Private IP address
  - Specs (CPU/RAM/disk)
  - Root password (reveal button)
  - SSH connection command
  - Creation date
  - Hourly/monthly cost
  - Current uptime hours
- **FR-4.2:** Start VPS action (if stopped)
- **FR-4.3:** Stop VPS action (if running)
- **FR-4.4:** Restart VPS action
- **FR-4.5:** Delete VPS action with confirmation modal
  - Releases public IP back to pool
  - Releases hardware resources
  - Soft-delete record (sets deleted_at)

#### 4.1.5 Web Console
- **FR-5.1:** "Open Console" button on VPS detail page
- **FR-5.2:** Web-based terminal using xterm.js
- **FR-5.3:** WebSocket connection to hardware controller
- **FR-5.4:** Execute `lxc exec <container> -- /bin/bash` for SSH-like access
- **FR-5.5:** Display connection status (connected/disconnected)

#### 4.1.6 Billing & Credits
- **FR-6.1:** "Top Up Credits" page with preset amounts ($10, $25, $50, $100)
- **FR-6.2:** For MVP: Clicking "Top Up" instantly adds credits (no payment gateway)
- **FR-6.3:** Display billing transactions history:
  - Date
  - Type (credit purchase, VPS charge)
  - Amount
  - Balance after
  - Description
- **FR-6.4:** Hourly billing cron job (runs every hour):
  - For each running VPS, calculate hours since last_billed_at
  - Deduct credits: hours × hourly_rate
  - Create billing_transaction record
  - Update customer.credits
  - If credits < 0, stop VPS and notify customer
- **FR-6.5:** Show low credit warning when balance < 2 days of usage

### 4.2 Admin Dashboard (Enhancements)

#### 4.2.1 Hardware Management
- **FR-7.1:** Add new hardware server form:
  - Name
  - IP address
  - API key
  - Total CPU cores
  - Total memory (GB)
  - Total disk (GB)
- **FR-7.2:** Test connection button (calls /health endpoint)
- **FR-7.3:** Edit hardware details
- **FR-7.4:** Remove hardware (only if no VPS instances assigned)
- **FR-7.5:** View hardware capacity utilization:
  - CPU: X/Y cores used
  - Memory: X/Y GB used
  - Disk: X/Y GB used
  - IPs: X/Y assigned

#### 4.2.2 IP Address Management
- **FR-8.1:** Per hardware, "Add IPs" form:
  - Single IP input
  - OR bulk input (IP range: 157.173.122.74-78)
- **FR-8.2:** Display all IPs per hardware with status:
  - Available (green)
  - Assigned (blue, show VPS name)
  - Reserved (gray)
- **FR-8.3:** Manually release IP (admin override)
- **FR-8.4:** Alert when available IPs < 5 per hardware

#### 4.2.3 VPS Tier Management
- **FR-9.1:** Create new tier form:
  - Name
  - Slug (auto-generated from name)
  - CPU cores
  - Memory (GB)
  - Disk (GB)
  - Monthly price (auto-calculate hourly rate)
- **FR-9.2:** Edit existing tier
- **FR-9.3:** Activate/deactivate tier (toggle)
- **FR-9.4:** Reorder tiers (sort_order)
- **FR-9.5:** Delete tier (only if no active VPS instances use it)

#### 4.2.4 System Monitoring
- **FR-10.1:** System alerts page showing:
  - IP shortage warnings
  - Hardware offline alerts
  - Low capacity warnings
- **FR-10.2:** Acknowledge alert button
- **FR-10.3:** Dashboard overview:
  - Total customers
  - Total active VPS instances
  - Total revenue (sum of all credits purchased)
  - Total system capacity vs. used
- **FR-10.4:** View all customer VPS instances across all hardware
- **FR-10.5:** Admin can manually add credits to any customer account

---

## 5. Non-Functional Requirements

### 5.1 Performance
- **NFR-1:** VPS creation completes within 60 seconds (90th percentile)
- **NFR-2:** Dashboard loads within 2 seconds
- **NFR-3:** Web console latency < 200ms

### 5.2 Security
- **NFR-4:** All passwords stored with bcrypt (cost factor 10)
- **NFR-5:** API keys encrypted in database
- **NFR-6:** JWT tokens expire after 7 days
- **NFR-7:** HTTPS only for all communication
- **NFR-8:** Rate limiting: 100 requests/minute per customer

### 5.3 Reliability
- **NFR-9:** System should handle hardware failure gracefully (mark offline, alert admin)
- **NFR-10:** Database backups daily
- **NFR-11:** Billing cron job must be idempotent (no double-charging)

### 5.4 Scalability
- **NFR-12:** Support up to 10 hardware servers in MVP
- **NFR-13:** Support up to 1,000 customers in MVP
- **NFR-14:** Support up to 50 VPS instances per hardware server

### 5.5 Usability
- **NFR-15:** Customer web app must be mobile-responsive
- **NFR-16:** Admin dashboard optimized for desktop (1920×1080)

---

## 6. Out of Scope (Phase 2+)

- **Snapshots & Backups:** Manual or scheduled VPS snapshots
- **Resize VPS:** Change tier without losing data
- **Firewall Rules:** Customer-configurable iptables
- **Block Storage:** Attach additional volumes
- **Private Networking:** VPCs for customer isolation
- **SSH Key Management:** Upload public keys (MVP uses password-only)
- **Email Notifications:** VPS status changes, low credits
- **Payment Gateway:** Real Stripe integration
- **API for Customers:** Programmatic VPS management
- **Teams/Organizations:** Multi-user accounts
- **Custom Images:** Upload own OS images
- **Monitoring Graphs:** CPU/RAM/disk usage over time

---

## 7. Success Criteria

The MVP is considered successful when:

1. A customer can register, top up credits (fake), create a VPS, and SSH into it
2. Admin can add hardware, add IPs, define tiers, and monitor system
3. Billing cron job correctly deducts credits hourly
4. System auto-selects hardware with capacity and available IPs
5. Web console provides terminal access to VPS
6. No critical bugs in core workflows

---

## 8. Deployment

- **Customer Web App:** Deploy on Vercel or similar (Next.js hosting)
- **Admin Dashboard:** Deploy on Vercel or similar (separate deployment)
- **PostgreSQL:** Docker container on a VPS (persistent volume)
- **Hardware Controllers:** Already deployed on VDS servers

---

## 9. Timeline Estimate

- **Phase 1 (Foundation):** 1 week
- **Phase 2 (Customer VPS Creation):** 1 week
- **Phase 3 (Admin Tier & IP Management):** 3-4 days
- **Phase 4 (Billing & Polish):** 3-4 days
- **Phase 5 (Web Console & Testing):** 3-4 days

**Total MVP Development:** ~3-4 weeks

---

## 10. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Hardware controller API changes | High | Version API, maintain backward compatibility |
| IP exhaustion | High | Alert system when < 5 IPs available |
| Billing cron failure | Critical | Logging, monitoring, manual fallback |
| Customer abuse (spam VPS creation) | Medium | Rate limiting, require email verification in Phase 2 |
| Database connection issues | High | Connection pooling, retry logic |

---

**End of SRS**
