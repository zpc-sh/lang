# 🔄 LANG Secrets Migration Checklist

Use this checklist to migrate from exposed `.env` to secure secrets management.

## Pre-Migration Checks

- [ ] Backup current `.env` file
- [ ] Note which services are using live/production keys
- [ ] Inform team about upcoming key rotation
- [ ] Schedule migration during low-traffic period

## Migration Steps

### 1. Secure Current Secrets
- [ ] Run migration script: `./scripts/migrate_secrets.sh`
- [ ] Verify backup created in `.secrets/`
- [ ] Confirm `.env` file removed
- [ ] Check new `.env.local` created

### 2. Update Git Security
- [ ] Verify `.gitignore` updated with:
  - [ ] `.env`
  - [ ] `.env.*` (except `.env.example`)
  - [ ] `.secrets/`
  - [ ] `deploy/secrets*.yml`
- [ ] Run `git status` - no secrets should appear
- [ ] Commit `.gitignore` changes

### 3. Rotate Compromised Keys

#### Stripe
- [ ] Log into [Stripe Dashboard](https://dashboard.stripe.com/apikeys)
- [ ] Click "Roll secret key" for live key
- [ ] Copy new secret key
- [ ] Update `deploy/secrets.production.yml`
- [ ] Get new webhook signing secret
- [ ] Update production deployment

#### Database
- [ ] Create new database user/password
- [ ] Update connection string
- [ ] Test new credentials
- [ ] Remove old database user

#### Other Services
- [ ] Rotate OpenAI API key
- [ ] Rotate SendGrid API key
- [ ] Update any other API keys

### 4. Development Environment Setup
- [ ] Get Stripe TEST keys from dashboard
- [ ] Update `.env.local` with test keys:
  ```
  STRIPE_SECRET_KEY=sk_test_...
  STRIPE_PUBLISHABLE_KEY=pk_test_...
  ```
- [ ] Run `source load_secrets.sh`
- [ ] Run `mix run scripts/validate_secrets.exs`
- [ ] Run `./scripts/setup_stripe.sh` with test keys

### 5. Production Deployment
- [ ] Review `deploy/secrets.production.yml`
- [ ] Ensure all new keys are included
- [ ] Deploy to Fly.io:
  ```bash
  ./scripts/deploy_secrets.sh
  fly secrets deploy
  ```
- [ ] Verify application still works
- [ ] Check logs for any errors

### 6. Git History Cleanup (if needed)
- [ ] Check if secrets were committed:
  ```bash
  git log -p .env | grep -E "sk_live|SECRET"
  ```
- [ ] If found, follow GitHub's guide for removing sensitive data
- [ ] Consider force-pushing cleaned history
- [ ] Notify team about history rewrite

### 7. Team Communication
- [ ] Send migration summary to team
- [ ] Update any documentation
- [ ] Share new development setup instructions
- [ ] Schedule security training if needed

## Post-Migration Verification

### Immediate (Day 1)
- [ ] All services functioning correctly
- [ ] No exposed secrets in current codebase
- [ ] Development environment working
- [ ] CI/CD pipelines updated

### Week 1
- [ ] Monitor for any failed API calls
- [ ] Check Stripe webhook logs
- [ ] Review application error logs
- [ ] Confirm no unauthorized access

### Month 1
- [ ] Set up key rotation reminders (90 days)
- [ ] Document lessons learned
- [ ] Update security policies
- [ ] Plan regular security audits

## Rollback Plan

If issues occur:

1. **For production keys**:
   - Restore from `.secrets/env.backup.*`
   - Revert Fly secrets
   - Investigate and fix issues
   - Retry migration

2. **For development**:
   - Use `.env.example` as template
   - Regenerate development keys
   - Document any issues found

## Success Criteria

- [ ] No secrets in Git repository
- [ ] All environments using appropriate keys (test/live)
- [ ] Team can develop without production access
- [ ] Automated validation passing
- [ ] Documentation updated
- [ ] No service disruptions

## Notes Section

Use this space to document any issues or special considerations during migration:

```
Date: _______________
Migrated by: _______________

Issues encountered:
- 

Special considerations:
- 

Follow-up needed:
- 
```

---

**Remember**: This migration improves security significantly. Take your time and do it right!