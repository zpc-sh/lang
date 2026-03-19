# 🔒 LANG Security Documentation

Welcome to the LANG platform security documentation. This section covers all aspects of security, with a primary focus on secrets management and data protection.

## 📚 Documentation Index

### Secrets Management
- **[Complete Secrets Management Guide](./secrets-management.md)** - Comprehensive guide covering all aspects of secrets protection
- **[Quick Reference Card](./secrets-quick-reference.md)** - One-page reference for daily development
- **[Migration Checklist](./secrets-migration-checklist.md)** - Step-by-step checklist for migrating from exposed secrets
- **[Secrets Protection Overview](./secrets-protection.md)** - Original protection guide with platform-specific details

### Security Tools & Scripts
Located in `/scripts/`:
- `secure_secrets.sh` - Complete security setup script
- `migrate_secrets.sh` - Migrate from exposed .env to secure setup
- `validate_secrets.exs` - Validate all required secrets are present
- `setup_stripe.sh` - Set up Stripe with proper key management
- `deploy_secrets.sh` - Deploy secrets to production (Fly.io)

### Best Practices
- [Key Rotation Schedule](#key-rotation-schedule)
- [Emergency Procedures](#emergency-procedures)
- [Compliance Requirements](#compliance-requirements)

## 🚀 Getting Started

### For New Developers

1. Start with the [Quick Reference Card](./secrets-quick-reference.md)
2. Run the setup script: `./scripts/secure_secrets.sh`
3. Read the [Complete Guide](./secrets-management.md) for detailed understanding

### For Existing Projects

1. Use the [Migration Checklist](./secrets-migration-checklist.md)
2. Run: `./scripts/migrate_secrets.sh`
3. Follow the post-migration verification steps

## 🔑 Key Security Principles

1. **Never Commit Secrets** - Use environment variables exclusively
2. **Separate Environments** - Different keys for dev/test/prod
3. **Rotate Regularly** - 90-day rotation for API keys
4. **Encrypt at Rest** - Use provided encryption tools
5. **Audit Everything** - Log and monitor secret access

## 📊 Security Status Dashboard

Run this command to check your current security status:

```bash
# Check for exposed secrets
git ls-files | xargs grep -l "sk_live\|pk_live\|SECRET" || echo "✅ No secrets in git"

# Validate configuration
mix run scripts/validate_secrets.exs

# Check file permissions
ls -la .secrets/ 2>/dev/null || echo "⚠️  No .secrets directory"
```

## 🚨 Emergency Contacts

- **Security Incidents**: security@lang-platform.dev
- **Key Compromise**: Use the [Emergency Procedures](./secrets-management.md#emergency-procedures)
- **Questions**: Check documentation first, then ask in #security channel

## 📅 Key Rotation Schedule

| Secret Type | Rotation Period | Last Rotated | Next Rotation |
|-------------|----------------|--------------|---------------|
| API Keys | 90 days | ___________ | ___________ |
| Database Password | 180 days | ___________ | ___________ |
| Encryption Keys | 1 year | ___________ | ___________ |
| Webhook Secrets | 90 days | ___________ | ___________ |

## 🔍 Quick Security Audit

```bash
#!/bin/bash
# Run this monthly

echo "🔍 LANG Security Audit - $(date)"
echo "================================"

# Check for exposed secrets
echo -n "Git repository clean: "
git ls-files | xargs grep -l "sk_live\|SECRET" &>/dev/null && echo "❌ EXPOSED SECRETS!" || echo "✅ Pass"

# Check file permissions
echo -n "Secrets directory secure: "
[[ $(stat -f "%OLp" .secrets 2>/dev/null || stat -c "%a" .secrets 2>/dev/null) == "700" ]] && echo "✅ Pass" || echo "❌ Fix permissions"

# Check environment
echo -n "Using test keys in dev: "
[[ $STRIPE_SECRET_KEY == sk_test_* ]] && echo "✅ Pass" || echo "❌ Wrong keys!"

# Validate all secrets
echo -n "All secrets configured: "
mix run scripts/validate_secrets.exs &>/dev/null && echo "✅ Pass" || echo "❌ Missing secrets"
```

## 📚 Additional Resources

### Internal
- [Architecture Documentation](../architecture/index.md)
- [API Security](../api/security.md)
- [Deployment Guide](../guides/deployment.md)

### External
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Phoenix Security](https://hexdocs.pm/phoenix/security.html)
- [Stripe Security](https://stripe.com/docs/security)

## 🎯 Security Roadmap

### Implemented ✅
- [x] Secrets management system
- [x] Environment separation
- [x] Encryption utilities
- [x] Validation tools
- [x] Migration scripts

### Planned 📋
- [ ] Hardware Security Module (HSM) integration
- [ ] Automated key rotation
- [ ] Security scanning in CI/CD
- [ ] Penetration testing
- [ ] SOC 2 Type II certification

---

**Security is a journey, not a destination.** Keep learning, stay vigilant, and always prioritize the protection of user data.