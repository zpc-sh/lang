# 🔐 LANG Secrets Quick Reference

## 🚀 Quick Start Commands

```bash
# Initial setup (run once)
./scripts/secure_secrets.sh
cp .env.example .env.local

# Daily development
source load_secrets.sh          # Load secrets
mix phx.server                  # Start app

# Validation
mix run scripts/validate_secrets.exs
```

## 📁 File Structure

```
.env.local      → Your dev secrets (gitignored)
.env.example    → Template file (committed)
.env            → NEVER USE (deprecated)
```

## 🔑 Environment Variables

### Required Secrets
```bash
# Generate these with mix phx.gen.secret
SECRET_KEY_BASE=              # 64+ chars
LIVE_VIEW_SIGNING_SALT=       # 32 chars  
ASH_AUTHENTICATION_SECRET=    # 64 chars
ENCRYPTION_KEY=               # Base64 encoded 32 bytes

# Database
DATABASE_URL=postgres://user:pass@localhost:5432/lang_dev

# Stripe (use TEST keys for dev!)
STRIPE_SECRET_KEY=sk_test_...
STRIPE_PUBLISHABLE_KEY=pk_test_...
```

## 🛠️ Common Tasks

### Add a New Secret
```bash
# 1. Add to template
echo "NEW_API_KEY=placeholder" >> .env.example

# 2. Add to your local env
echo "NEW_API_KEY=actual-value" >> .env.local

# 3. Reload
source load_secrets.sh
```

### Switch Environments
```bash
source load_secrets.sh .env.test   # For testing
source load_secrets.sh .env.local  # Back to dev
```

### Deploy to Production
```bash
# Edit deploy/secrets.production.yml
./scripts/deploy_secrets.sh
fly secrets deploy
```

## ⚠️ Security Rules

### NEVER DO THIS
```bash
❌ git add .env
❌ echo "secret" > .env
❌ use sk_live_ keys in development
❌ share secrets via Slack/email
❌ hardcode secrets in code
```

### ALWAYS DO THIS
```bash
✅ use .env.local for development
✅ use sk_test_ keys for Stripe dev
✅ run validate_secrets.exs
✅ rotate keys every 90 days
✅ use source load_secrets.sh
```

## 🚨 Emergency

### If Secrets Are Exposed
1. **Rotate immediately** (Stripe dashboard → Roll key)
2. **Update production**: `fly secrets set KEY=new_value`
3. **Check logs** for unauthorized access
4. **Notify team** if customer data affected

### Check for Exposed Secrets
```bash
# In files
git ls-files | xargs grep -l "sk_live"

# In history  
git log -p | grep -E "(secret|key|password)"
```

## 🔍 Debugging

### Secret Not Loading?
```bash
# Check if loaded
env | grep MY_SECRET

# Reload
source load_secrets.sh

# Validate all
mix run scripts/validate_secrets.exs
```

### Wrong Environment?
```bash
# Check Stripe key type
echo $STRIPE_SECRET_KEY | head -c 7
# Should show sk_test for dev
```

## 📞 Help

- Docs: `docs/security/secrets-management.md`
- Script: `./scripts/secure_secrets.sh --help`
- Team: #security channel

---
Remember: **When in doubt, ask!** Better safe than sorry with secrets.