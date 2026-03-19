# 🔐 LANG Secrets Management Documentation

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [File Structure](#file-structure)
4. [Development Workflow](#development-workflow)
5. [Production Deployment](#production-deployment)
6. [Security Tools](#security-tools)
7. [Emergency Procedures](#emergency-procedures)
8. [Best Practices](#best-practices)
9. [Troubleshooting](#troubleshooting)
10. [Compliance & Auditing](#compliance--auditing)

## Overview

The LANG platform implements a comprehensive secrets management system designed to protect sensitive configuration data such as API keys, database credentials, and encryption keys. This system ensures that secrets are never exposed in version control and provides tools for secure handling across all environments.

### Key Principles

- **Separation of Environments**: Different secrets for development, testing, and production
- **No Secrets in Code**: All sensitive data stored in environment variables
- **Encryption at Rest**: Tools for encrypting secrets locally
- **Audit Trail**: Tracking and validation of secret usage
- **Easy Rotation**: Simple process for updating compromised keys

## Quick Start

### Initial Setup (New Developers)

1. **Run the security setup script**:
   ```bash
   ./scripts/secure_secrets.sh
   ```

2. **Copy the example environment file**:
   ```bash
   cp .env.example .env.local
   ```

3. **Generate required secrets**:
   ```bash
   # Generate Phoenix secrets
   mix phx.gen.secret                    # SECRET_KEY_BASE
   mix phx.gen.secret 32                 # LIVE_VIEW_SIGNING_SALT
   mix phx.gen.secret 64                 # ASH_AUTHENTICATION_SECRET
   
   # Generate encryption key in IEx
   iex> :crypto.strong_rand_bytes(32) |> Base.encode64()
   ```

4. **Get development API keys**:
   - Stripe TEST keys: https://dashboard.stripe.com/test/apikeys
   - Other services: Use development/sandbox environments

5. **Load and validate secrets**:
   ```bash
   source load_secrets.sh
   mix run scripts/validate_secrets.exs
   ```

### Migration from Exposed Secrets

If you have an existing `.env` file with production secrets:

```bash
./scripts/migrate_secrets.sh
```

This will:
- Backup your secrets securely
- Create proper development environment
- Remove exposed files
- Update `.gitignore`

## File Structure

```
project_root/
├── .env.example                    # Template with all variables (committed)
├── .env.local                      # Development secrets (gitignored)
├── .env.test                       # Test environment (gitignored)
├── .secrets/                       # Encrypted secrets directory (gitignored)
│   ├── encrypt_secret.sh           # Encryption utility
│   ├── decrypt_secret.sh           # Decryption utility
│   └── env.backup.*                # Backup files
├── deploy/
│   ├── secrets.production.yml.example  # Production template
│   └── secrets.production.yml          # Production secrets (gitignored)
├── scripts/
│   ├── secure_secrets.sh           # Security setup script
│   ├── migrate_secrets.sh          # Migration tool
│   ├── validate_secrets.exs        # Validation script
│   ├── setup_stripe.sh             # Stripe setup
│   └── deploy_secrets.sh           # Deployment script
└── docs/
    └── security/
        └── secrets-protection.md   # This documentation
```

### Environment Files Explained

| File | Purpose | Git Status | When to Use |
|------|---------|------------|-------------|
| `.env.example` | Template showing all required variables | ✅ Committed | Reference for new developers |
| `.env.local` | Development secrets | ❌ Gitignored | Local development |
| `.env.test` | Test environment secrets | ❌ Gitignored | Running tests |
| `.env` | Legacy file | ❌ Never use | Deprecated |

## Development Workflow

### Daily Development

1. **Start your day**:
   ```bash
   # Load development secrets
   source load_secrets.sh
   
   # Verify everything is configured
   mix run scripts/validate_secrets.exs
   ```

2. **Start services**:
   ```bash
   # Start Docker services (Postgres, Redis)
   docker-compose up -d
   
   # Start Phoenix
   mix phx.server
   ```

3. **Switch environments**:
   ```bash
   # For testing
   source load_secrets.sh .env.test
   mix test
   
   # Back to development
   source load_secrets.sh .env.local
   ```

### Adding New Secrets

1. **Update `.env.example`**:
   ```bash
   # Add the new variable with a placeholder
   echo "NEW_SERVICE_API_KEY=your-key-here" >> .env.example
   ```

2. **Add to your local environment**:
   ```bash
   echo "NEW_SERVICE_API_KEY=actual-dev-key" >> .env.local
   ```

3. **Update validation script**:
   ```elixir
   # In scripts/validate_secrets.exs
   @required_secrets [
     # ... existing secrets
     "NEW_SERVICE_API_KEY"
   ]
   ```

4. **Document the secret**:
   - Add to this documentation
   - Update setup instructions
   - Note any special requirements

### Using Test vs Production Keys

| Service | Development | Production | Notes |
|---------|-------------|------------|-------|
| Stripe | `sk_test_...` | `sk_live_...` | Use test mode for all development |
| Database | Local PostgreSQL | Managed database | Different credentials per environment |
| Redis | Local Redis | Managed Redis | Optional in development |
| Email | Sandbox/logs | Real SMTP | Use letter_opener in dev |

## Production Deployment

### Fly.io Deployment

1. **Prepare secrets file**:
   ```bash
   cp deploy/secrets.production.yml.example deploy/secrets.production.yml
   # Edit with production values
   ```

2. **Deploy secrets**:
   ```bash
   ./scripts/deploy_secrets.sh
   fly secrets deploy
   ```

3. **Verify deployment**:
   ```bash
   fly secrets list
   ```

### Other Platform Deployments

#### Heroku
```bash
# Set individual secrets
heroku config:set SECRET_KEY_BASE="..."
heroku config:set DATABASE_URL="..."

# Or bulk import
cat deploy/secrets.production.yml | \
  sed 's/: /=/' | \
  xargs heroku config:set
```

#### AWS ECS/Fargate
```bash
# Using AWS Secrets Manager
aws secretsmanager create-secret \
  --name lang/production \
  --secret-string file://deploy/secrets.production.yml

# Reference in task definition
{
  "secrets": [{
    "name": "SECRET_KEY_BASE",
    "valueFrom": "arn:aws:secretsmanager:region:account:secret:lang/production:SECRET_KEY_BASE::"
  }]
}
```

#### Kubernetes
```yaml
# Create secret from file
kubectl create secret generic lang-secrets \
  --from-env-file=deploy/secrets.production.yml

# Or create manually
apiVersion: v1
kind: Secret
metadata:
  name: lang-secrets
type: Opaque
stringData:
  SECRET_KEY_BASE: "your-secret-base"
  DATABASE_URL: "postgres://..."
```

#### Docker Swarm
```bash
# Create secrets
echo "your-secret" | docker secret create secret_key_base -

# Use in service
docker service create \
  --secret secret_key_base \
  --env SECRET_KEY_BASE_FILE=/run/secrets/secret_key_base \
  lang-app
```

## Security Tools

### Encryption Utilities

**Encrypt a secret**:
```bash
./.secrets/encrypt_secret.sh my_api_key "sk_live_secret_value"
```

**Decrypt a secret**:
```bash
./.secrets/decrypt_secret.sh my_api_key
```

**Master key management**:
```bash
# Generate new master key
openssl rand -base64 32 > ~/.lang_master_key
chmod 600 ~/.lang_master_key

# Backup master key (store securely!)
cat ~/.lang_master_key | gpg -c > master_key.gpg
```

### Validation Tools

**Check all secrets**:
```bash
mix run scripts/validate_secrets.exs
```

**Audit for exposed secrets**:
```bash
# Check current files
git ls-files | xargs grep -l "sk_live\|pk_live\|SECRET" || echo "✓ Clean"

# Check git history
git log -p | grep -E "(sk_|pk_|secret|password|key)" | head -20
```

**Monitor secret usage**:
```elixir
# In your application
defmodule Lang.Secrets.Monitor do
  require Logger
  
  def log_access(secret_name, context) do
    Logger.info("Secret accessed", 
      secret: secret_name,
      context: context,
      timestamp: DateTime.utc_now()
    )
  end
end
```

## Emergency Procedures

### Compromised Secrets Response

If secrets are exposed or compromised:

1. **Immediate Actions** (within 5 minutes):
   ```bash
   # Rotate affected keys immediately
   # For Stripe: https://dashboard.stripe.com/apikeys
   # Click "Roll secret key"
   
   # Update production
   fly secrets set STRIPE_SECRET_KEY="new_key" --stage
   fly secrets deploy
   ```

2. **Assessment** (within 1 hour):
   - Check access logs for unauthorized use
   - Identify scope of exposure
   - Document timeline of events

3. **Communication** (within 24 hours):
   - Notify affected users if required
   - Update security team
   - File incident report

4. **Prevention** (within 1 week):
   - Review how exposure occurred
   - Update procedures
   - Additional training if needed

### Git History Cleanup

If secrets were committed to git:

```bash
# Option 1: BFG Repo-Cleaner (recommended)
brew install bfg
bfg --delete-files .env
git push --force

# Option 2: git filter-branch
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch .env" \
  --prune-empty --tag-name-filter cat -- --all

# Clean up
git for-each-ref --format="delete %(refname)" refs/original | git update-ref --stdin
git reflog expire --expire=now --all
git gc --prune=now --aggressive
```

## Best Practices

### Key Rotation Schedule

| Secret Type | Rotation Frequency | Notes |
|-------------|-------------------|-------|
| API Keys | 90 days | Automate if possible |
| Database Passwords | 180 days | Coordinate with ops |
| Encryption Keys | Yearly | Requires data migration |
| Webhook Secrets | 90 days | Update endpoints |
| JWT Secrets | 180 days | Plan for token expiry |

### Access Control

1. **Principle of Least Privilege**:
   - Developers: Test keys only
   - CI/CD: Deployment keys only
   - Production: Restricted access

2. **Secret Sharing**:
   ```bash
   # Never share via:
   # ❌ Email
   # ❌ Slack/Discord
   # ❌ Git commits
   
   # Use instead:
   # ✅ Password managers (1Password, Bitwarden)
   # ✅ Encrypted files (GPG)
   # ✅ Secret management services
   ```

3. **Audit Trail**:
   - Log all secret access
   - Review logs monthly
   - Alert on anomalies

### Development Guidelines

1. **Never hardcode secrets**:
   ```elixir
   # ❌ BAD
   defmodule MyModule do
     @api_key "sk_live_abcd1234"
   end
   
   # ✅ GOOD
   defmodule MyModule do
     def api_key, do: System.get_env("API_KEY")
   end
   ```

2. **Use configuration modules**:
   ```elixir
   # config/runtime.exs
   config :lang, :stripe,
     secret_key: System.fetch_env!("STRIPE_SECRET_KEY"),
     webhook_secret: System.fetch_env!("STRIPE_WEBHOOK_SECRET")
   ```

3. **Fail fast on missing secrets**:
   ```elixir
   # Use fetch_env! to fail at startup
   System.fetch_env!("REQUIRED_SECRET")
   
   # Instead of silent failures
   System.get_env("REQUIRED_SECRET") || ""  # ❌ BAD
   ```

## Troubleshooting

### Common Issues

**Issue: "Missing required environment variable"**
```bash
# Solution 1: Check if secrets are loaded
env | grep SECRET_KEY_BASE

# Solution 2: Reload secrets
source load_secrets.sh

# Solution 3: Validate all secrets
mix run scripts/validate_secrets.exs
```

**Issue: "No such price" (Stripe)**
```bash
# You're mixing test/live keys and products
# Check your key type:
echo $STRIPE_SECRET_KEY | head -c 7
# Should show "sk_test" for development

# Recreate products with correct keys
./scripts/setup_stripe.sh
```

**Issue: "Permission denied" on scripts**
```bash
# Fix permissions
chmod +x scripts/*.sh
chmod +x .secrets/*.sh
```

**Issue: Secrets not persisting between terminal sessions**
```bash
# Add to your shell profile (~/.zshrc or ~/.bashrc)
alias lang-dev="cd /path/to/lang && source load_secrets.sh"
```

### Debugging Secret Loading

```elixir
# Add debug module
defmodule Lang.Secrets.Debug do
  def check_all do
    [
      "SECRET_KEY_BASE",
      "DATABASE_URL",
      "STRIPE_SECRET_KEY"
    ]
    |> Enum.map(fn key ->
      value = System.get_env(key)
      status = if value, do: "✓ Set", else: "✗ Missing"
      preview = if value, do: "#{String.slice(value, 0, 10)}...", else: "N/A"
      
      {key, status, preview}
    end)
    |> Enum.each(fn {key, status, preview} ->
      IO.puts("#{status} #{key}: #{preview}")
    end)
  end
end

# Run in IEx
Lang.Secrets.Debug.check_all()
```

## Compliance & Auditing

### Regulatory Requirements

For compliance with regulations (GDPR, PCI-DSS, HIPAA):

1. **Documentation Requirements**:
   - Document all systems accessing secrets
   - Maintain access logs for 1 year
   - Regular access reviews (quarterly)

2. **Technical Controls**:
   ```elixir
   # Implement secret access logging
   defmodule Lang.Compliance.SecretAuditor do
     use GenServer
     require Logger
     
     def log_access(secret_name, accessor, reason) do
       event = %{
         timestamp: DateTime.utc_now(),
         secret: secret_name,
         accessor: accessor,
         reason: reason,
         environment: Application.get_env(:lang, :environment)
       }
       
       Logger.info("SECRET_ACCESS", event)
       
       # Store in audit table
       %Lang.Audit.SecretAccess{}
       |> Lang.Audit.SecretAccess.changeset(event)
       |> Lang.Repo.insert!()
     end
   end
   ```

3. **Regular Audits**:
   ```bash
   # Monthly audit script
   mix run scripts/audit_secrets.exs --month 2024-01
   ```

### Security Certifications

To maintain security certifications:

1. **SOC 2 Type II**:
   - Encrypted secrets at rest ✓
   - Access logging ✓
   - Regular rotation ✓
   - Separation of duties ✓

2. **ISO 27001**:
   - Risk assessment documented
   - Incident response plan
   - Regular training
   - Continuous improvement

3. **PCI-DSS** (if handling payments):
   - No cardholder data in logs
   - Encrypted transmission
   - Access control
   - Regular penetration testing

## Additional Resources

### Internal Documentation
- [Architecture Overview](../architecture/index.md)
- [Deployment Guide](../guides/deployment.md)
- [Development Setup](../guides/getting-started.md)

### External Resources
- [Phoenix Security Guide](https://hexdocs.pm/phoenix/security.html)
- [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
- [12 Factor App - Config](https://12factor.net/config)
- [Stripe Security Best Practices](https://stripe.com/docs/security/guide)
- [AWS Secrets Manager Best Practices](https://docs.aws.amazon.com/secretsmanager/latest/userguide/best-practices.html)

### Security Contacts

- **Security Team**: security@lang-platform.dev
- **Incident Response**: incidents@lang-platform.dev
- **Compliance Questions**: compliance@lang-platform.dev

---

**Remember**: Security is everyone's responsibility. When in doubt, ask for help rather than taking risks with secrets.