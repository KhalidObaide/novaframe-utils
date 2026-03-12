# Phase 2 Complete: Customer Portal Authentication & Credits

**Status**: ✅ Complete  
**Date**: March 2, 2026

## Overview

Phase 2 successfully delivered a complete customer-facing portal with authentication and credits management. The portal is a separate Next.js application that shares the PostgreSQL database with the hardware-admin system through the `@redcloud/db` package.

## Deliverables

### 1. Customer Portal Application
- **Location**: `customer-portal/`
- **Tech Stack**: Next.js 16 (App Router), TypeScript, Tailwind CSS
- **Port**: 3001 (separate from hardware-admin on port 3000)

### 2. Authentication System
✅ JWT-based authentication using `jose` library
✅ Secure password hashing with `bcryptjs`
✅ Session management with HTTP-only cookies
✅ Protected routes via Next.js middleware
✅ Automatic redirect to login for unauthenticated users

**API Routes:**
- `POST /api/auth/register` - Create new customer account
  - Validates email uniqueness
  - Enforces minimum 8-character password
  - Creates customer record with 0 initial credits
  - Returns JWT token and sets auth cookie
  
- `POST /api/auth/login` - Sign in existing customer
  - Validates credentials
  - Returns JWT token and sets auth cookie
  
- `POST /api/auth/logout` - Sign out customer
  - Clears auth cookie
  
- `GET /api/auth/session` - Get current user data
  - Returns fresh user data from database
  - Used for client-side session validation

### 3. Credits Management System
✅ View current credit balance on dashboard
✅ Add credits via simple top-up interface
✅ Quick-select buttons ($10, $25, $50, $100)
✅ Transaction history recording in database
✅ Real-time balance updates

**API Routes:**
- `POST /api/credits/topup` - Add credits to account
  - Validates amount > 0
  - Uses database transaction for atomicity
  - Creates billing_transaction record
  - Updates customer credits balance

**Note**: Payment integration is intentionally simplified for MVP. The top-up is simulated (no actual payment processing via Stripe or similar). This will be enhanced in future phases when billing becomes critical.

### 4. Customer Dashboard
✅ Clean, modern UI with Tailwind CSS
✅ Account information display (email, name)
✅ Credit balance prominently displayed
✅ VPS instances section (empty state for Phase 3)
✅ Logout functionality
✅ Responsive design

### 5. Database Integration
✅ Shares `@redcloud/db` package with hardware-admin
✅ Uses existing `customers` table from Phase 0 schema
✅ Creates `billing_transactions` records for all credit operations
✅ No schema changes required (existing schema was sufficient)

## Files Created

### Core Application
- `customer-portal/src/app/layout.tsx` - Root layout
- `customer-portal/src/app/page.tsx` - Dashboard page
- `customer-portal/src/app/globals.css` - Global styles
- `customer-portal/src/app/login/page.tsx` - Login page
- `customer-portal/src/app/register/page.tsx` - Registration page

### API Routes
- `customer-portal/src/app/api/auth/register/route.ts`
- `customer-portal/src/app/api/auth/login/route.ts`
- `customer-portal/src/app/api/auth/logout/route.ts`
- `customer-portal/src/app/api/auth/session/route.ts`
- `customer-portal/src/app/api/credits/topup/route.ts`

### Utilities & Middleware
- `customer-portal/src/lib/auth.ts` - JWT utilities (create, verify, session management)
- `customer-portal/src/lib/password.ts` - Password hashing utilities
- `customer-portal/src/middleware.ts` - Route protection middleware

### Configuration
- `customer-portal/.env.local` - Environment variables
- `customer-portal/package.json` - Dependencies and scripts
- `customer-portal/tsconfig.json` - TypeScript configuration
- `customer-portal/README.md` - Documentation

## Technical Details

### Authentication Flow
1. User registers or logs in
2. Server validates credentials and creates JWT token
3. JWT stored in HTTP-only cookie (7-day expiration)
4. Middleware checks for auth cookie on protected routes
5. API routes verify JWT and fetch fresh user data

### Credits Flow
1. Customer views balance on dashboard
2. Enters amount or clicks quick-select button
3. POST to `/api/credits/topup` with amount
4. Server validates session and amount
5. Database transaction:
   - Updates customer credits (increment)
   - Creates billing_transaction record
6. Returns updated balance to client
7. Dashboard updates in real-time

### Security Features
- HTTP-only cookies prevent XSS attacks
- JWT signed with secret key
- Passwords hashed with bcrypt (salt rounds: 10)
- Middleware redirects unauthenticated users
- API routes verify session before processing requests

## Database Schema Usage

### Customers Table
```prisma
model Customer {
  id           String   @id @default(uuid())
  email        String   @unique
  passwordHash String
  fullName     String
  company      String?
  credits      Decimal  @default(0) @db.Decimal(10, 2)
  createdAt    DateTime @default(now())
  updatedAt    DateTime @updatedAt
}
```

### Billing Transactions Table
```prisma
model BillingTransaction {
  id          String   @id @default(uuid())
  customerId  String
  type        String   // 'credit' | 'charge'
  amount      Decimal  @db.Decimal(10, 2)
  description String
  createdAt   DateTime @default(now())
  
  customer Customer @relation(fields: [customerId], references: [id])
}
```

## Testing

### Build Test
```bash
cd customer-portal
npm install
npm run build
# ✅ Build successful
```

### Manual Testing Checklist
- [ ] Register new customer account
- [ ] Login with created account
- [ ] View dashboard with $0.00 credits
- [ ] Add $10 credits
- [ ] Verify balance updates to $10.00
- [ ] Add $25 more credits
- [ ] Verify balance updates to $35.00
- [ ] Logout
- [ ] Attempt to access dashboard (should redirect to login)
- [ ] Login again (session restored)

## Running the Portal

```bash
cd customer-portal
npm run dev
```

Access at: http://localhost:3001

## Architecture Notes

### Separation from Hardware Admin
The customer portal is a completely separate Next.js application that:
- Runs on different port (3001 vs 3000)
- Has its own authentication system (JWT vs admin auth)
- Shares database but targets different tables
- Can be deployed independently

### Middleware Simplification
The middleware was simplified to avoid Edge runtime limitations:
- Only checks for presence of auth cookie
- Full JWT verification happens in API routes (Node.js runtime)
- This is acceptable for MVP; can be enhanced later

### TypeScript Challenges Resolved
- Fixed path mapping: `@/*` → `./src/*`
- Used `require()` for CommonJS db package in ES modules
- Added explicit `any` typing for Prisma transaction callbacks
- Double type assertion for JWT payload casting

## Dependencies Added

### Production
- `bcryptjs` ^3.0.3 - Password hashing
- `jose` ^6.1.3 - JWT operations (Edge runtime compatible)
- `jsonwebtoken` ^9.0.3 - Legacy JWT support
- `@redcloud/db` file:../packages/db - Shared database client

### Development
- `@types/bcryptjs` - TypeScript types for bcryptjs

## Next Steps (Phase 3)

Phase 2 is complete and ready for testing. When approved, Phase 3 will add:

1. **VPS Tier Selection**
   - Fetch and display available tiers from database
   - Show pricing, resources, and descriptions
   - Allow customers to select a tier

2. **VPS Deployment**
   - Deploy VPS from selected tier
   - Assign IP address from pool
   - Deduct credits based on tier pricing
   - Create vps_instance record

3. **VPS Management**
   - View all owned VPS instances
   - Start/stop instances
   - View instance details (IP, resources, status)
   - Delete instances (with credit refund logic)

4. **Billing Integration**
   - Hourly billing for running instances
   - Automatic credit deduction
   - Low balance warnings
   - Billing history page

## Known Limitations (Intentional for MVP)

1. **No Payment Integration**: Credits are added manually, no Stripe/PayPal
2. **No Email Verification**: Accounts are immediately active
3. **No Password Reset**: Would require email integration
4. **No Multi-Factor Authentication**: Basic password auth only
5. **No Rate Limiting**: Should be added before production
6. **Simplified Session Validation**: Middleware only checks cookie presence

These limitations are acceptable for MVP and will be addressed in future iterations based on priority.

---

**Phase 2 Status**: ✅ **COMPLETE AND READY FOR TESTING**
