/**
 * Stripe Integration for LANG Universal Text Intelligence Platform
 *
 * Handles payment processing, subscription management, and checkout flows
 * using Stripe Elements for secure payment collection.
 */

// Initialize Stripe with publishable key from environment (guard if Stripe.js not loaded)
let stripe = null;
try {
  if (window.Stripe && window.stripePublishableKey) {
    stripe = window.Stripe(window.stripePublishableKey);
  } else {
    console.warn('[Stripe] Global Stripe.js not found or publishable key missing; payments disabled on this page');
  }
} catch (e) {
  console.warn('[Stripe] initialization failed; payments disabled:', e);
}

// Stripe Elements configuration
const stripeElementsConfig = {
  appearance: {
    theme: 'stripe',
    variables: {
      colorPrimary: '#2563eb',
      colorBackground: '#ffffff',
      colorText: '#1f2937',
      colorDanger: '#ef4444',
      fontFamily: '"Inter", -apple-system, BlinkMacSystemFont, sans-serif',
      spacingUnit: '4px',
      borderRadius: '8px'
    },
    rules: {
      '.Input': {
        boxShadow: '0 1px 3px 0 rgba(0, 0, 0, 0.1)',
        border: '1px solid #d1d5db'
      },
      '.Input:focus': {
        borderColor: '#2563eb',
        boxShadow: '0 0 0 3px rgba(37, 99, 235, 0.1)'
      }
    }
  }
};

/**
 * Payment Form Handler
 * Manages the subscription upgrade/downgrade flow
 */
class PaymentFormHandler {
  constructor() {
    this.elements = null;
    this.paymentElement = null;
    this.isProcessing = false;
    this.selectedPlan = null;
  }

  /**
   * Initialize payment form for plan selection
   */
  async initializePaymentForm(planType, clientSecret) {
    try {
      if (!stripe) {
        this.displayError('Payment system unavailable. Please refresh or try again later.');
        return;
      }
      this.selectedPlan = planType;

      // Create Elements instance
      this.elements = stripe.elements({
        clientSecret: clientSecret,
        ...stripeElementsConfig
      });

      // Create and mount payment element
      this.paymentElement = this.elements.create('payment');
      this.paymentElement.mount('#payment-element');

      // Handle real-time validation errors
      this.paymentElement.on('change', (event) => {
        this.displayError(event.error ? event.error.message : '');
      });

      console.log(`Payment form initialized for ${planType} plan`);
    } catch (error) {
      console.error('Failed to initialize payment form:', error);
      this.displayError('Failed to load payment form. Please refresh and try again.');
    }
  }

  /**
   * Process payment submission
   */
  async processPayment(event) {
    event.preventDefault();

    if (this.isProcessing) {
      return;
    }

    if (!stripe) {
      this.displayError('Payment system unavailable. Please refresh or try again later.');
      return;
    }

    this.isProcessing = true;
    this.setLoadingState(true);

    try {
      // Confirm payment with Stripe
      const { error, paymentIntent } = await stripe.confirmPayment({
        elements: this.elements,
        confirmParams: {
          return_url: `${window.location.origin}/dashboard?payment=success`,
          receipt_email: this.getUserEmail()
        },
        redirect: 'if_required'
      });

      if (error) {
        this.handlePaymentError(error);
      } else if (paymentIntent && paymentIntent.status === 'succeeded') {
        this.handlePaymentSuccess(paymentIntent);
      }
    } catch (error) {
      console.error('Payment processing error:', error);
      this.displayError('An unexpected error occurred. Please try again.');
    } finally {
      this.isProcessing = false;
      this.setLoadingState(false);
    }
  }

  /**
   * Handle successful payment
   */
  handlePaymentSuccess(paymentIntent) {
    console.log('Payment succeeded:', paymentIntent.id);

    // Hide payment form
    this.hidePaymentForm();

    // Show success message
    this.displaySuccess(`Successfully upgraded to ${this.selectedPlan} plan!`);

    // Trigger LiveView update
    window.dispatchEvent(new CustomEvent('payment:success', {
      detail: {
        paymentIntentId: paymentIntent.id,
        plan: this.selectedPlan
      }
    }));

    // Reload page after brief delay to show updated dashboard
    setTimeout(() => {
      window.location.reload();
    }, 2000);
  }

  /**
   * Handle payment errors
   */
  handlePaymentError(error) {
    console.error('Payment failed:', error);

    let errorMessage = 'Payment failed. Please try again.';

    // Provide specific error messages
    switch (error.code) {
      case 'card_declined':
        errorMessage = 'Your card was declined. Please try a different payment method.';
        break;
      case 'insufficient_funds':
        errorMessage = 'Insufficient funds. Please try a different card.';
        break;
      case 'expired_card':
        errorMessage = 'Your card has expired. Please use a different card.';
        break;
      case 'incorrect_cvc':
        errorMessage = 'Your card security code is incorrect. Please check and try again.';
        break;
      case 'processing_error':
        errorMessage = 'An error occurred while processing your card. Please try again.';
        break;
      default:
        errorMessage = error.message || errorMessage;
    }

    this.displayError(errorMessage);
  }

  /**
   * Set loading state for form
   */
  setLoadingState(isLoading) {
    const submitButton = document.getElementById('submit-payment');
    const spinner = document.getElementById('payment-spinner');

    if (submitButton) {
      submitButton.disabled = isLoading;
      submitButton.textContent = isLoading ? 'Processing...' : 'Complete Upgrade';
    }

    if (spinner) {
      spinner.style.display = isLoading ? 'inline-block' : 'none';
    }
  }

  /**
   * Display error message
   */
  displayError(message) {
    const errorElement = document.getElementById('payment-errors');
    if (errorElement) {
      errorElement.textContent = message;
      errorElement.style.display = message ? 'block' : 'none';
    }
  }

  /**
   * Display success message
   */
  displaySuccess(message) {
    const successElement = document.getElementById('payment-success');
    if (successElement) {
      successElement.textContent = message;
      successElement.style.display = 'block';
    }

    // Also remove any existing error messages
    this.displayError('');
  }

  /**
   * Hide payment form
   */
  hidePaymentForm() {
    const formElement = document.getElementById('payment-form');
    if (formElement) {
      formElement.style.display = 'none';
    }
  }

  /**
   * Get user email from page
   */
  getUserEmail() {
    const emailMeta = document.querySelector('meta[name="user-email"]');
    return emailMeta ? emailMeta.content : null;
  }
}

/**
 * Subscription Management
 * Handles subscription cancellation and reactivation
 */
class SubscriptionManager {
  /**
   * Cancel subscription with confirmation
   */
  async cancelSubscription() {
    const confirmed = confirm(
      'Are you sure you want to cancel your subscription? ' +
      'You will lose access to premium features at the end of your billing period.'
    );

    if (!confirmed) {
      return;
    }

    try {
      // Trigger LiveView event for cancellation
      window.dispatchEvent(new CustomEvent('subscription:cancel'));
    } catch (error) {
      console.error('Failed to cancel subscription:', error);
      alert('Failed to cancel subscription. Please contact support.');
    }
  }

  /**
   * Reactivate cancelled subscription
   */
  async reactivateSubscription() {
    try {
      // Trigger LiveView event for reactivation
      window.dispatchEvent(new CustomEvent('subscription:reactivate'));
    } catch (error) {
      console.error('Failed to reactivate subscription:', error);
      alert('Failed to reactivate subscription. Please try again or contact support.');
    }
  }
}

/**
 * Billing Portal Integration
 * Direct customers to Stripe's billing portal for advanced management
 */
class BillingPortal {
  /**
   * Redirect to Stripe billing portal
   */
  async openBillingPortal() {
    try {
      // Trigger LiveView event to create portal session
      window.dispatchEvent(new CustomEvent('billing:open_portal'));
    } catch (error) {
      console.error('Failed to open billing portal:', error);
      alert('Unable to open billing portal. Please try again.');
    }
  }
}

/**
 * Usage Analytics Integration
 * Real-time usage monitoring and alerts
 */
class UsageMonitor {
  constructor() {
    this.usageThresholds = {
      warning: 0.8,  // 80%
      critical: 0.95  // 95%
    };
  }

  /**
   * Update usage display and show warnings if needed
   */
  updateUsageDisplay(current, limit, plan) {
    const usagePercentage = current / limit;
    const usageElement = document.getElementById('usage-progress');
    const warningElement = document.getElementById('usage-warning');

    if (usageElement) {
      // Update progress bar
      const progressBar = usageElement.querySelector('.progress-bar');
      if (progressBar) {
        progressBar.style.width = `${Math.min(usagePercentage * 100, 100)}%`;

        // Color coding
        if (usagePercentage >= this.usageThresholds.critical) {
          progressBar.className = 'progress-bar bg-red-500';
        } else if (usagePercentage >= this.usageThresholds.warning) {
          progressBar.className = 'progress-bar bg-yellow-500';
        } else {
          progressBar.className = 'progress-bar bg-green-500';
        }
      }

      // Update text
      const usageText = usageElement.querySelector('.usage-text');
      if (usageText) {
        usageText.textContent = `${current.toLocaleString()} / ${limit.toLocaleString()} requests used`;
      }
    }

    // Show warnings
    if (warningElement) {
      if (usagePercentage >= this.usageThresholds.critical) {
        warningElement.innerHTML = `
          <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded">
            <strong>Usage Critical!</strong> You've used ${Math.round(usagePercentage * 100)}% of your monthly requests.
            <a href="#" onclick="paymentHandler.showUpgradeOptions()" class="underline">Upgrade now</a> to avoid service interruption.
          </div>
        `;
        warningElement.style.display = 'block';
      } else if (usagePercentage >= this.usageThresholds.warning) {
        warningElement.innerHTML = `
          <div class="bg-yellow-100 border border-yellow-400 text-yellow-700 px-4 py-3 rounded">
            <strong>Usage Warning:</strong> You've used ${Math.round(usagePercentage * 100)}% of your monthly requests.
            <a href="#" onclick="paymentHandler.showUpgradeOptions()" class="underline">Consider upgrading</a> to ensure uninterrupted service.
          </div>
        `;
        warningElement.style.display = 'block';
      } else {
        warningElement.style.display = 'none';
      }
    }
  }
}

// Initialize global instances
window.paymentHandler = new PaymentFormHandler();
window.subscriptionManager = new SubscriptionManager();
window.billingPortal = new BillingPortal();
window.usageMonitor = new UsageMonitor();

// Phoenix LiveView integration
document.addEventListener('DOMContentLoaded', function() {
  // Listen for LiveView events
  window.addEventListener('phx:payment_form_init', (event) => {
    const { plan, client_secret } = event.detail;
    paymentHandler.initializePaymentForm(plan, client_secret);
  });

  window.addEventListener('phx:usage_updated', (event) => {
    const { current, limit, plan } = event.detail;
    usageMonitor.updateUsageDisplay(current, limit, plan);
  });

  // Handle payment form submission
  const paymentForm = document.getElementById('payment-form');
  if (paymentForm) {
    paymentForm.addEventListener('submit', (event) => {
      paymentHandler.processPayment(event);
    });
  }
});

// Export for use in other modules
export { PaymentFormHandler, SubscriptionManager, BillingPortal, UsageMonitor };
