#!/bin/bash
# Setup Stripe products and prices for LANG platform

set -e

echo "🚀 LANG Stripe Setup Script"
echo "=========================="

# Check for required environment variables
if [ -z "$STRIPE_SECRET_KEY" ]; then
    echo "❌ Error: STRIPE_SECRET_KEY not set"
    echo "Please set your Stripe secret key in .env file"
    exit 1
fi

# Detect if using live or test keys
if [[ $STRIPE_SECRET_KEY == sk_live_* ]]; then
    echo "⚠️  WARNING: You are using LIVE Stripe keys!"
    echo "This will create real products in your production Stripe account."
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Setup cancelled."
        exit 0
    fi
else
    echo "✅ Using TEST Stripe keys (safe for development)"
fi

# Install Stripe CLI if not present
if ! command -v stripe &> /dev/null; then
    echo "📦 Installing Stripe CLI..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install stripe/stripe-cli/stripe
    else
        echo "Please install Stripe CLI manually: https://stripe.com/docs/stripe-cli"
        exit 1
    fi
fi

echo ""
echo "Creating LANG products in Stripe..."
echo ""

# Create products
echo "1️⃣ Creating Pro Plan product..."
PRO_PRODUCT=$(stripe products create \
  --name="LANG Pro" \
  --description="Universal intelligence beyond text - 10,000 requests/month" \
  --metadata[plan_type]="pro" \
  --metadata[managed_by]="lang_platform" \
  -d "active=true" \
  | grep -oE '"id": "[^"]*"' | head -1 | cut -d'"' -f4)

echo "   Created product: $PRO_PRODUCT"

echo "2️⃣ Creating Business Plan product..."
BUSINESS_PRODUCT=$(stripe products create \
  --name="LANG Business" \
  --description="Secure team workspace with collaboration - Per user pricing" \
  --metadata[plan_type]="business" \
  --metadata[managed_by]="lang_platform" \
  --metadata[billing_type]="per_user" \
  -d "active=true" \
  | grep -oE '"id": "[^"]*"' | head -1 | cut -d'"' -f4)

echo "   Created product: $BUSINESS_PRODUCT"

# Create prices
echo ""
echo "3️⃣ Creating Pro Plan price ($49/month)..."
PRO_PRICE=$(stripe prices create \
  --product=$PRO_PRODUCT \
  --currency=usd \
  --unit-amount=4900 \
  --recurring[interval]=month \
  --metadata[plan_type]="pro" \
  | grep -oE '"id": "[^"]*"' | head -1 | cut -d'"' -f4)

echo "   Created price: $PRO_PRICE"

echo "4️⃣ Creating Business Plan price ($25/user/month)..."
BUSINESS_PRICE=$(stripe prices create \
  --product=$BUSINESS_PRODUCT \
  --currency=usd \
  --unit-amount=2500 \
  --recurring[interval]=month \
  --recurring[usage_type]=per_unit \
  --metadata[plan_type]="business" \
  --metadata[billing_type]="per_user" \
  | grep -oE '"id": "[^"]*"' | head -1 | cut -d'"' -f4)

echo "   Created price: $BUSINESS_PRICE"

# Create webhook endpoint
echo ""
echo "5️⃣ Setting up webhook endpoint..."
WEBHOOK_URL="${APP_HOST:-https://lang.nocsi.com}/webhooks/stripe"

WEBHOOK_ENDPOINT=$(stripe webhook_endpoints create \
  --url=$WEBHOOK_URL \
  --enabled-events customer.subscription.created,customer.subscription.updated,customer.subscription.deleted,invoice.payment_succeeded,invoice.payment_failed,checkout.session.completed \
  | grep -oE '"secret": "[^"]*"' | head -1 | cut -d'"' -f4)

echo "   Created webhook endpoint: $WEBHOOK_URL"

# Output results
echo ""
echo "✅ Stripe setup complete!"
echo ""
echo "Add these values to your .env file:"
echo "=================================="
echo "STRIPE_PRO_PRICE_ID=$PRO_PRICE"
echo "STRIPE_BUSINESS_PRICE_ID=$BUSINESS_PRICE" 
echo "STRIPE_WEBHOOK_SECRET=$WEBHOOK_ENDPOINT"
echo ""
echo "Next steps:"
echo "1. Update your .env file with the values above"
echo "2. Restart your Phoenix server"
echo "3. Test the billing flow at /dashboard"
echo ""
echo "🎉 Happy billing!"