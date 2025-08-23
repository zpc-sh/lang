<div align="center">
  <img src="priv/static/images/lang_logo.svg" alt="LANG Logo" width="600">
  <h1>LANG Production Deployment Guide 🚀</h1>
</div>

Complete guide for deploying LANG Universal Text Intelligence Platform to production using Fly.io, with Stripe billing, Rust NIFs, and comprehensive monitoring.

## 📋 Overview

Your LANG system includes:
- **Elixir 1.15.7 + Phoenix** with LiveView
- **Ash Framework** for sophisticated data management
- **4 Rust NIFs** for high-performance text processing
- **Stripe Integration** with comprehensive billing plans
- **Oban** for background job processing (including your LANG 2.0 orchestration)
- **Health Monitoring** with comprehensive system checks
- **File Upload Handling** with persistent storage

## 🎯 Deployment Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Fly.io VM     │    │   Database      │    │   File Storage  │
│   1GB RAM       │    │   Neon/Supabase │    │   Fly Volume    │
│   Elixir + NIFs │◄──►│   PostgreSQL    │    │   1GB Uploads   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         ▲
         │ HTTPS
         ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Cloudflare    │    │   Stripe API    │    │   Monitoring    │
│   CDN + DNS     │    │   Billing       │    │   Health Checks │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

**Estimated Monthly Cost:** ~$6-8 + Stripe transaction fees

## 🛠️ Prerequisites

### Required Tools
```bash
# Install Fly.io CLI
curl -L https://fly.io/install.sh | sh

# Install Stripe CLI (for webhook testing)
brew install stripe/stripe-cli/stripe

# Verify installations
fly version
stripe --version
mix --version
cargo --version
```

### Required Accounts
- [Fly.io account](https://fly.io/app/sign-up) (deployment platform)
- [Neon](https://neon.tech) or [Supabase](https://supabase.com) (database)
- [Stripe account](https://stripe.com) (payment processing)
- [Cloudflare account](https://cloudflare.com) (optional, for custom domain)

## 🚀 Step-by-Step Deployment

### Step 1: Environment Setup

1. **Copy the environment template:**
```bash
cp .env.production.template .env.production
```

2. **Configure required variables in `.env.production`:**
```bash
# Database (required)
DATABASE_URL="postgresql://user:pass@hostname:5432/database"

# Generated secret (required)
SECRET_KEY_BASE="$(mix phx.gen.secret)"

# Domain configuration
PHX_HOST="lang.nocsi.com"

# Stripe configuration (required for billing)
STRIPE_SECRET_KEY="sk_live_..."
STRIPE_WEBHOOK_SECRET="whsec_..."
STRIPE_STARTER_PRICE_ID="price_..."
STRIPE_PRO_PRICE_ID="price_..."
STRIPE_ENTERPRISE_PRICE_ID="price_..."
```

3. **Load environment:**
```bash
source .env.production
```

### Step 2: Database Setup

#### Option A: Neon (Recommended)
```bash
# 1. Create account at https://neon.tech
# 2. Create new project
# 3. Copy connection string to DATABASE_URL
# 4. Neon provides 0.5GB free tier
```

#### Option B: Supabase
```bash
# 1. Create account at https://supabase.com
# 2. Create new project
# 3. Go to Settings > Database
# 4. Copy connection string (use connection pooling)
# 5. Supabase provides 500MB free tier
```

### Step 3: Stripe Configuration

1. **Create Stripe products and prices:**
```bash
# Login to Stripe CLI
stripe login

# Create products (run these in Stripe dashboard or via CLI)
# Pro Plan - $29/month
stripe prices create \
  --unit-amount 2900 \
  --currency usd \
  --recurring-interval month \
  --product-data name="LANG Pro Plan"

# Enterprise Plan - $99/month  
stripe prices create \
  --unit-amount 9900 \
  --currency usd \
  --recurring-interval month \
  --product-data name="LANG Enterprise Plan"
```

2. **Create webhook endpoint:**
- Go to Stripe Dashboard > Developers > Webhooks
- Add endpoint: `https://lang.nocsi.com/webhooks/stripe`
- Select events: `customer.*`, `invoice.*`, `payment_intent.*`, `checkout.session.completed`
- Copy webhook secret to `STRIPE_WEBHOOK_SECRET`

### Step 4: Initial Deployment

1. **Make scripts executable:**
```bash
make make-scripts-executable
```

2. **Run initial deployment:**
```bash
make deploy-initial
```

This script will:
- ✅ Check all prerequisites
- ✅ Create Fly.io application
- ✅ Set up secrets and environment variables
- ✅ Create storage volume for uploads
- ✅ Compile Rust NIFs
- ✅ Build and deploy application
- ✅ Run database migrations
- ✅ Set up custom domain
- ✅ Verify deployment health

### Step 5: Domain Configuration

1. **Add CNAME record:**
```
Type: CNAME
Name: lang.nocsi.com (or your domain)
Value: lang-floral-firefly-7929.fly.dev
```

2. **Verify domain:**
```bash
fly domains list
dig lang.nocsi.com
```

## 📊 Post-Deployment Verification

### Health Check
```bash
curl https://lang.nocsi.com/health
```

Expected response:
```json
{
  "status": "ok",
  "timestamp": "2024-01-01T00:00:00Z",
  "version": "0.1.0",
  "uptime": "0d 0h 5m 30s",
  "checks": {
    "database": {"status": "ok", "message": "Database connection healthy"},
    "redis": {"status": "ok", "message": "Redis connection healthy"},
    "disk_space": {"status": "ok", "message": "Disk usage: 15%"},
    "memory": {"status": "ok", "message": "Memory usage: 45%"}
  }
}
```

### Stripe Webhook Test
```bash
# Test webhook locally first
stripe listen --forward-to localhost:4000/webhooks/stripe

# Test production webhook
stripe events resend evt_test_webhook
```

### Application Features Test
1. Visit `https://lang.nocsi.com`
2. Test text analysis functionality
3. Test user authentication
4. Test billing pages (if implemented)
5. Check dashboard and API portal

## 🔄 Regular Deployments

### Full Deployment (Recommended)
```bash
make deploy
```
- Runs tests
- Compiles NIFs
- Builds assets
- Deploys with health checks
- Runs migrations

### Quick Deployment
```bash
make deploy-quick
```
- Skips tests (faster)
- Still compiles NIFs
- Good for hotfixes

### Rollback
```bash
make rollback
```

## 📈 Monitoring & Maintenance

### View Logs
```bash
make logs
# or
fly logs --lines 100
```

### Access Production Console
```bash
make console
# or
fly ssh console -C "./bin/lang remote"
```

### Application Status
```bash
make status
# or
fly status
```

### Database Migrations
```bash
make migrate
# or
fly ssh console -C "./bin/lang eval Lang.Release.migrate"
```

## 🔒 Security Checklist

- [ ] **Secrets Management**: All sensitive data in environment variables
- [ ] **HTTPS Only**: Force SSL in production
- [ ] **Database Security**: SSL connections, strong passwords
- [ ] **Rate Limiting**: Configured per billing tier
- [ ] **CORS**: Restricted to your domains
- [ ] **Webhook Signatures**: Stripe webhook signature verification
- [ ] **Authentication**: Ash authentication properly configured
- [ ] **File Uploads**: Size limits and type validation

## 💰 Cost Optimization

### Current Setup Cost Breakdown
```
Fly.io VM (1GB):        $5.70/month
Fly.io Volume (1GB):    $0.15/month
Neon Database (free):   $0.00/month
Cloudflare:             $0.00/month
Total Infrastructure:   ~$6/month
```

### Revenue Example (100 customers)
```
Revenue (100 × $29):    $2,900/month
Stripe fees (~3%):      $87/month
Infrastructure:         $6/month
Net Revenue:            $2,807/month
```

### Cost Optimization Tips
1. **Auto-stop machines** when idle (already configured)
2. **Use free database tiers** (Neon/Supabase)
3. **Monitor usage** via Fly.io dashboard
4. **Scale gradually** based on demand

## 🚨 Troubleshooting

### Common Issues

#### Rust NIFs Compilation Fails
```bash
# Check Rust installation
cargo --version

# Clean and recompile
mix rustler.clean
mix rustler.compile
```

#### Health Check Fails
```bash
# Check logs
fly logs --lines 50

# Check application status
fly status

# Access console
fly ssh console
```

#### Database Connection Issues
```bash
# Test connection
fly ssh console -C "/app/bin/lang eval 'Ecto.Adapters.SQL.query(Lang.Repo, \"SELECT 1\")'"

# Check DATABASE_URL format
echo $DATABASE_URL
```

#### Stripe Webhooks Not Working
```bash
# Check webhook endpoint
curl -X POST https://lang.nocsi.com/webhooks/stripe \
  -H "Content-Type: application/json" \
  -d '{"test": "webhook"}'

# Verify webhook secret
echo $STRIPE_WEBHOOK_SECRET
```

### Getting Help

1. **Check logs**: `make logs`
2. **Fly.io status**: `fly status`
3. **Health endpoint**: `curl https://lang.nocsi.com/health`
4. **Console access**: `make console`
5. **Community**: [Fly.io community](https://community.fly.io)

## 📚 Additional Resources

- [Fly.io Phoenix Deployment Guide](https://fly.io/docs/elixir/getting-started/)
- [Stripe API Documentation](https://stripe.com/docs/api)
- [Ash Framework Documentation](https://ash-hq.org/)
- [Phoenix Deployment Guide](https://hexdocs.pm/phoenix/deployment.html)

## 🎉 Success!

Your LANG Universal Text Intelligence Platform is now live at:
- **Production URL**: https://lang.nocsi.com
- **Health Check**: https://lang.nocsi.com/health  
- **API Portal**: https://lang.nocsi.com/api-portal
- **Stripe Webhooks**: https://lang.nocsi.com/webhooks/stripe

The platform is ready to:
- Process text with high-performance Rust NIFs
- Handle user authentication via Ash
- Process payments through Stripe
- Scale automatically based on demand
- Monitor health and performance

**Total deployment time**: ~15-20 minutes
**Monthly operating cost**: ~$6-8 + transaction fees
**Scalability**: Ready for thousands of users