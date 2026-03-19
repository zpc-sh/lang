# 🔐 LANG Secrets Protection Guide

## Overview

This guide covers how to properly manage and protect secrets in the LANG platform, including API keys, database credentials, and payment processor keys.

## ⚠️ Critical Security Alert

**NEVER commit real secrets to Git!** This includes:
- API keys (Stripe, OpenAI, etc.)
- Database passwords
- Encryption keys
- JWT secrets
- Any credentials

## Quick Start

Run the security setup script:

```bash
./scripts/secure_secrets.sh
```

This will:
1. Create secure environment files
2. Update .gitignore
3. Check for exposed secrets
4. Set up encryption tools
5. Create deployment templates

## Environment Files Structure

```
.env.example          # Template with all variables (committed to git)
.env.local           # Development secrets (git-ignored)
.env.test            # Test environment (git-ignored)
.env                 # DEPRECATED - do not use
.secrets/            # Encrypted secrets directory (git-ignored)
```

## Development Workflow

### 1. Initial Setup

```bash
# Copy the example file
cp .env.example .env.local

# Generate required secrets
mix phx.gen.secret                    # For SECRET_KEY_BASE
mix phx.gen.secret 32                 # For LIVE_VIEW_SIGNING_SALT
mix phx.gen.secret 64                 # For ASH_AUTHENTICATION_SECRET

# Generate encryption key in IEx
iex> :crypto.strong_rand_bytes(32) |> Base.encode64()
```

### 2. Loading Secrets

```bash
# Load secrets into your shell
source load_secrets.sh

# Or specify a different file
source load_secrets.sh .env.test
```

### 3. Validating Secrets

```bash
# Check all required secrets are set
mix run scripts/validate_secrets.exs
```

## Production Deployment

### Using Fly.io

1. Create production secrets file:
```bash
cp deploy/secrets.production.yml.example deploy/secrets.production.yml
# Edit with your production values
```

2. Deploy to Fly:
```bash
./scripts/deploy_secrets.sh
fly secrets deploy
```

### Using Other Platforms

#### Heroku
```bash
heroku config:set SECRET_KEY_BASE="your-secret"
heroku config:set DATABASE_URL="postgres://..."
```

#### AWS
Use AWS Secrets Manager or Parameter Store:
```bash
aws secretsmanager create-secret \
  --name lang/production/stripe_api_key \
  --secret-string "sk_live_..."
```

#### Kubernetes
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: lang-secrets
type: Opaque
data:
  secret_key_base: <base64-encoded-value>
  stripe_api_key: <base64-encoded-value>
```

## Stripe Keys Management

### Development vs Production

| Environment | Key Type | Prefix | Safe to Commit? |
|------------|----------|---------|-----------------|
| Development | Test Secret | `sk_test_` | No |
| Development | Test Publishable | `pk_test_` | No* |
| Production | Live Secret | `sk_live_` | NEVER |
| Production | Live Publishable | `pk_live_` | No* |

\* While publishable keys are meant for client-side use, it's still best practice to keep them in environment variables.

### Setting Up Stripe

1. For development (test mode):
```bash
STRIPE_SECRET_KEY=sk_test_...
STRIPE_PUBLISHABLE_KEY=pk_test_...
./scripts/setup_stripe.sh
```

2. For production:
- Use Fly secrets or your platform's secret management
- Never put live keys in .env files
- Set up webhook endpoints in Stripe dashboard

## Encryption for Sensitive Data

### Encrypting Secrets Locally

```bash
# Encrypt a secret
./.secrets/encrypt_secret.sh stripe_key "sk_live_xxxxx"

# Decrypt a secret
./.secrets/decrypt_secret.sh stripe_key
```

### Application-Level Encryption

LANG uses field-level encryption for sensitive data:

```elixir
defmodule Lang.Encrypted do
  use Cloak.Ecto.Binary, vault: Lang.Vault
end

# In your schema
schema "users" do
  field :email, Lang.Encrypted
  field :api_key, Lang.Encrypted
end
```

## Security Best Practices

### 1. Key Rotation

Rotate keys regularly:
- API keys: Every 90 days
- Database passwords: Every 180 days
- Encryption keys: Yearly (with proper migration)

### 2. Access Control

- Use different keys for different environments
- Limit production access to essential personnel
- Use IAM roles instead of keys where possible

### 3. Monitoring

Set up alerts for:
- Failed authentication attempts
- Unusual API usage patterns
- Access to production secrets

### 4. Git Security

If you accidentally committed secrets:

```bash
# Remove from history (destructive!)
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch .env" \
  --prune-empty --tag-name-filter cat -- --all

# Force push (coordinate with team)
git push --force --all
git push --force --tags

# Better: Rotate all exposed keys immediately
```

## Troubleshooting

### Missing Secrets Error

```
** (RuntimeError) Missing required environment variable: STRIPE_SECRET_KEY
```

Solution:
```bash
source load_secrets.sh
mix run scripts/validate_secrets.exs
```

### Wrong Environment Keys

```
Stripe::InvalidRequestError: No such price: 'price_xxx'
```

You're using test keys with live price IDs or vice versa. Check your Stripe dashboard.

### Permission Denied

```
-bash: ./.secrets/encrypt_secret.sh: Permission denied
```

Solution:
```bash
chmod +x .secrets/*.sh
```

## Emergency Procedures

If secrets are compromised:

1. **Immediately rotate affected keys**
2. Check logs for unauthorized access
3. Notify affected users if required
4. Update all deployment environments
5. Review and improve security practices

## Compliance

For regulatory compliance (GDPR, PCI-DSS, etc.):

- Log access to sensitive data
- Implement key rotation policies
- Use hardware security modules (HSM) for critical keys
- Regular security audits
- Document all secret access

## Additional Resources

- [Phoenix Security Guide](https://hexdocs.pm/phoenix/security.html)
- [OWASP Secrets Management](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
- [Stripe Security Best Practices](https://stripe.com/docs/security/guide)
- [12 Factor App - Config](https://12factor.net/config)

---

Remember: **Security is not optional**. Take the time to properly secure your secrets before deploying to production.