# LANG Deployment Quickstart 🚀

**Get your LANG Universal Text Intelligence Platform live in 15 minutes**

## 📋 Prerequisites Checklist

- [ ] [Fly.io account](https://fly.io/app/sign-up) (free)
- [ ] [Neon](https://neon.tech) or [Supabase](https://supabase.com) database (free tier)
- [ ] [Stripe account](https://stripe.com) for billing
- [ ] Domain ready (e.g., `lang.nocsi.com`)

## 🚀 Quick Deploy (15 minutes)

### Step 1: Environment Setup (3 minutes)
```bash
# 1. Install Fly CLI
curl -L https://fly.io/install.sh | sh
fly auth login

# 2. Copy environment template
cp .env.production.template .env.production

# 3. Set required variables in .env.production
DATABASE_URL="postgresql://user:pass@hostname:5432/database"
SECRET_KEY_BASE="$(mix phx.gen.secret)"
PHX_HOST="lang.nocsi.com"
STRIPE_SECRET_KEY="sk_live_..."
STRIPE_WEBHOOK_SECRET="whsec_..."
```

### Step 2: Deploy (10 minutes)
```bash
# Load environment and deploy
source .env.production
make deploy-initial
```

### Step 3: Verify (2 minutes)
```bash
# Check health
curl https://lang.nocsi.com/health

# Run full verification
./scripts/verify_deployment.sh
```

## 🎯 What Gets Deployed

Your deployment includes:

✅ **Elixir/Phoenix** application with LiveView  
✅ **4 Rust NIFs** for high-performance text processing  
✅ **Ash Framework** for sophisticated data management  
✅ **Stripe billing** with Pro ($29) and Enterprise ($99) plans  
✅ **Oban job processing** for background tasks  
✅ **File uploads** with persistent storage  
✅ **Health monitoring** with comprehensive checks  
✅ **Auto-scaling** and cost optimization  

## 💰 Cost Breakdown

```
Fly.io VM (1GB):        $5.70/month
Fly.io Volume (1GB):    $0.15/month  
Neon Database (free):   $0.00/month
Cloudflare DNS:         $0.00/month
-------------------------
Total: ~$6/month + Stripe fees (2.9% + $0.30)
```

**Revenue Example:** 100 customers × $29 = $2,807/month profit

## 🔧 Essential Commands

```bash
# Deploy updates
make deploy

# View logs
make logs

# SSH access
make ssh

# Health check
make health

# Rollback
make rollback
```

## 🎉 Success URLs

After deployment, your platform will be live at:

- **Main App**: https://lang.nocsi.com
- **Health Check**: https://lang.nocsi.com/health
- **API Portal**: https://lang.nocsi.com/api-portal  
- **Stripe Webhooks**: https://lang.nocsi.com/webhooks/stripe

## 🆘 Quick Troubleshooting

### Health Check Fails
```bash
fly logs --lines 50
fly status
```

### Database Issues  
```bash
fly ssh console -C "/app/bin/lang eval 'Ecto.Adapters.SQL.query(Lang.Repo, \"SELECT 1\")'"
```

### Rust NIFs Not Working
```bash
mix rustler.clean
mix rustler.compile
make deploy
```

## 📚 Full Documentation

For detailed configuration and troubleshooting, see:
- [`DEPLOYMENT_GUIDE.md`](./DEPLOYMENT_GUIDE.md) - Complete deployment guide
- [`.env.production.template`](./.env.production.template) - All environment variables
- [`scripts/`](./scripts/) - Deployment automation scripts

## 🔗 Support

- **Fly.io Issues**: [Community Forum](https://community.fly.io)
- **Stripe Setup**: [Documentation](https://stripe.com/docs)
- **Elixir/Phoenix**: [Guides](https://hexdocs.pm/phoenix)

---

**⚡ One-liner deployment:**
```bash
cp .env.production.template .env.production && \
nano .env.production && \
source .env.production && \
make deploy-initial
```

**🎯 Result:** Production-ready LANG platform with billing, monitoring, and auto-scaling in ~15 minutes!