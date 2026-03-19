defmodule Lang.Emails do
  @moduledoc """
  Email templates and delivery functions for LANG Universal Text Intelligence Platform.

  Provides email templates for authentication, notifications, and user engagement.
  All emails are responsive and branded with LANG's design system.

  Implements the AshAuthentication.Sender behaviour for confirmation emails.
  """

  use Phoenix.Component
  import Swoosh.Email
  alias Lang.Mailer

  @behaviour AshAuthentication.Sender

  @from_email "no-reply@nulity.com"
  @from_name "LANG Platform"
  @support_email "support@nulity.com"
  @base_url System.get_env("BASE_URL", "https://nulity.com")

  @doc """
  AshAuthentication.Sender callback for sending confirmation emails.
  """
  def send(user, token, opts) do
    case opts[:type] do
      :confirm ->
        send_confirmation_email(user, token)

      :reset ->
        send_password_reset_email(user, token)

      _ ->
        {:error, :unsupported_email_type}
    end
  end

  @doc """
  Sends a confirmation email to verify user's email address.
  """
  def send_confirmation_email(user, confirmation_token) do
    confirmation_url = "#{@base_url}/auth/confirm/#{confirmation_token}"

    new()
    |> to({user.name, user.email})
    |> from({@from_name, @from_email})
    |> subject("Welcome to LANG - Confirm Your Email")
    |> html_body(confirmation_email_html(user, confirmation_url))
    |> text_body(confirmation_email_text(user, confirmation_url))
    |> Mailer.deliver()
  end

  @doc """
  Sends a password reset email with reset link.
  """
  def send_password_reset_email(user, reset_token) do
    reset_url = "#{@base_url}/auth/reset-password/#{reset_token}"

    new()
    |> to({user.name, user.email})
    |> from({@from_name, @from_email})
    |> subject("LANG - Password Reset Request")
    |> html_body(password_reset_email_html(user, reset_url))
    |> text_body(password_reset_email_text(user, reset_url))
    |> Mailer.deliver()
  end

  @doc """
  Sends a welcome email after successful registration.
  """
  def send_welcome_email(user) do
    dashboard_url = "#{@base_url}/dashboard"

    new()
    |> to({user.name, user.email})
    |> from({@from_name, @from_email})
    |> subject("Welcome to LANG - Your Universal Text Intelligence Platform")
    |> html_body(welcome_email_html(user, dashboard_url))
    |> text_body(welcome_email_text(user, dashboard_url))
    |> Mailer.deliver()
  end

  @doc """
  Sends an email change confirmation email.
  """
  def send_email_change_confirmation(user, new_email, confirmation_token) do
    confirmation_url = "#{@base_url}/auth/confirm-email-change/#{confirmation_token}"

    new()
    |> to({user.name, new_email})
    |> from({@from_name, @from_email})
    |> subject("LANG - Confirm Your New Email Address")
    |> html_body(email_change_confirmation_html(user, new_email, confirmation_url))
    |> text_body(email_change_confirmation_text(user, new_email, confirmation_url))
    |> Mailer.deliver()
  end

  @doc """
  Sends a security alert email for important account changes.
  """
  def send_security_alert_email(user, action, details \\ %{}) do
    new()
    |> to({user.name, user.email})
    |> from({@from_name, @from_email})
    |> subject("LANG - Security Alert: #{format_security_action(action)}")
    |> html_body(security_alert_email_html(user, action, details))
    |> text_body(security_alert_email_text(user, action, details))
    |> Mailer.deliver()
  end

  # HTML Email Templates

  defp confirmation_email_html(user, confirmation_url) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Confirm Your Email - LANG</title>
        <style>
            #{base_email_styles()}
        </style>
    </head>
    <body>
        #{email_header()}
        <div class="container">
            <h1>Welcome to LANG, #{user.name}!</h1>

            <p>Thank you for joining the Universal Text Intelligence Platform. To get started, please confirm your email address by clicking the button below:</p>

            <div class="button-container">
                <a href="#{confirmation_url}" class="button button-primary">Confirm Email Address</a>
            </div>

            <p>This confirmation link will expire in 24 hours for security reasons.</p>

            <div class="features-preview">
                <h3>What you can do with LANG:</h3>
                <ul>
                    <li>🔍 Analyze text in 20+ formats with AI-powered insights</li>
                    <li>💬 Practice conversations with intelligent rehearsal scenarios</li>
                    <li>✍️ Analyze writing style and get improvement suggestions</li>
                    <li>🔄 Track document evolution with our Time Machine feature</li>
                    <li>🛠️ Integrate with your favorite editors via Language Server Protocol</li>
                </ul>
            </div>

            <p>If the button doesn't work, copy and paste this link into your browser:</p>
            <p class="link">#{confirmation_url}</p>
        </div>
        #{email_footer()}
    </body>
    </html>
    """
  end

  defp password_reset_email_html(user, reset_url) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Reset Your Password - LANG</title>
        <style>
            #{base_email_styles()}
        </style>
    </head>
    <body>
        #{email_header()}
        <div class="container">
            <h1>Password Reset Request</h1>

            <p>Hello #{user.name},</p>

            <p>We received a request to reset your password for your LANG account. Click the button below to create a new password:</p>

            <div class="button-container">
                <a href="#{reset_url}" class="button button-primary">Reset Password</a>
            </div>

            <div class="security-notice">
                <h3>🔒 Security Notice</h3>
                <p>This password reset link will expire in 1 hour for your security.</p>
                <p>If you didn't request this password reset, you can safely ignore this email. Your password will remain unchanged.</p>
            </div>

            <p>If the button doesn't work, copy and paste this link into your browser:</p>
            <p class="link">#{reset_url}</p>
        </div>
        #{email_footer()}
    </body>
    </html>
    """
  end

  defp welcome_email_html(user, dashboard_url) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Welcome to LANG</title>
        <style>
            #{base_email_styles()}
        </style>
    </head>
    <body>
        #{email_header()}
        <div class="container">
            <h1>🎉 Welcome to LANG, #{user.name}!</h1>

            <p>Your account is now active and ready to transform how you work with text. LANG provides universal text intelligence that goes beyond traditional analysis.</p>

            <div class="button-container">
                <a href="#{dashboard_url}" class="button button-primary">Go to Dashboard</a>
            </div>

            <div class="getting-started">
                <h3>🚀 Getting Started</h3>
                <div class="feature-card">
                    <h4>1. Try Text Analysis</h4>
                    <p>Upload any document or paste text to get instant AI-powered insights, suggestions, and quality metrics.</p>
                </div>

                <div class="feature-card">
                    <h4>2. Practice Conversations</h4>
                    <p>Use our Conversation Rehearsal Engine to practice job interviews, sales calls, and important discussions.</p>
                </div>

                <div class="feature-card">
                    <h4>3. Connect Your Editor</h4>
                    <p>Install our Language Server Protocol extension to get real-time text intelligence in VS Code, Neovim, and more.</p>
                </div>
            </div>

            <div class="subscription-info">
                <h3>Your Free Plan Includes:</h3>
                <ul>
                    <li>✅ 1,000 monthly analysis requests</li>
                    <li>✅ Access to all text formats (20+)</li>
                    <li>✅ Basic conversation rehearsal scenarios</li>
                    <li>✅ Writing style analysis</li>
                    <li>✅ LSP integration for popular editors</li>
                </ul>
            </div>

            <p>Have questions? Reply to this email or visit our <a href="#{@base_url}/docs">documentation</a> for detailed guides.</p>
        </div>
        #{email_footer()}
    </body>
    </html>
    """
  end

  defp email_change_confirmation_html(user, new_email, confirmation_url) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Confirm Email Change - LANG</title>
        <style>
            #{base_email_styles()}
        </style>
    </head>
    <body>
        #{email_header()}
        <div class="container">
            <h1>Confirm Your New Email</h1>

            <p>Hello #{user.name},</p>

            <p>We received a request to change your email address from <strong>#{user.email}</strong> to <strong>#{new_email}</strong>.</p>

            <p>To confirm this change, please click the button below:</p>

            <div class="button-container">
                <a href="#{confirmation_url}" class="button button-primary">Confirm Email Change</a>
            </div>

            <div class="security-notice">
                <h3>🔒 Security Notice</h3>
                <p>This confirmation link will expire in 24 hours.</p>
                <p>If you didn't request this email change, please contact our support team immediately at #{@support_email}</p>
            </div>

            <p>If the button doesn't work, copy and paste this link into your browser:</p>
            <p class="link">#{confirmation_url}</p>
        </div>
        #{email_footer()}
    </body>
    </html>
    """
  end

  defp security_alert_email_html(user, action, details) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Security Alert - LANG</title>
        <style>
            #{base_email_styles()}
        </style>
    </head>
    <body>
        #{email_header()}
        <div class="container">
            <h1>🔐 Security Alert</h1>

            <p>Hello #{user.name},</p>

            <p>We're writing to inform you about an important security event on your LANG account:</p>

            <div class="security-alert">
                <h3>#{format_security_action(action)}</h3>
                #{format_security_details(details)}
            </div>

            <p>If this was you, no further action is needed. If you don't recognize this activity, please:</p>

            <ul>
                <li>Change your password immediately</li>
                <li>Review your account settings</li>
                <li>Contact our support team at #{@support_email}</li>
            </ul>

            <div class="button-container">
                <a href="#{@base_url}/settings" class="button button-primary">Review Account Settings</a>
            </div>
        </div>
        #{email_footer()}
    </body>
    </html>
    """
  end

  # Text Email Templates

  defp confirmation_email_text(user, confirmation_url) do
    """
    Welcome to LANG, #{user.name}!

    Thank you for joining the Universal Text Intelligence Platform. To get started, please confirm your email address by visiting:

    #{confirmation_url}

    This confirmation link will expire in 24 hours for security reasons.

    What you can do with LANG:
    • Analyze text in 20+ formats with AI-powered insights
    • Practice conversations with intelligent rehearsal scenarios
    • Analyze writing style and get improvement suggestions
    • Track document evolution with our Time Machine feature
    • Integrate with your favorite editors via Language Server Protocol

    ---
    LANG Universal Text Intelligence Platform
    #{@base_url}
    """
  end

  defp password_reset_email_text(user, reset_url) do
    """
    Password Reset Request

    Hello #{user.name},

    We received a request to reset your password for your LANG account. Visit this link to create a new password:

    #{reset_url}

    This password reset link will expire in 1 hour for your security.

    If you didn't request this password reset, you can safely ignore this email. Your password will remain unchanged.

    ---
    LANG Universal Text Intelligence Platform
    #{@base_url}
    """
  end

  defp welcome_email_text(user, dashboard_url) do
    """
    Welcome to LANG, #{user.name}!

    Your account is now active and ready to transform how you work with text. LANG provides universal text intelligence that goes beyond traditional analysis.

    Get started: #{dashboard_url}

    Your Free Plan Includes:
    ✓ 1,000 monthly analysis requests
    ✓ Access to all text formats (20+)
    ✓ Basic conversation rehearsal scenarios
    ✓ Writing style analysis
    ✓ LSP integration for popular editors

    Have questions? Reply to this email or visit our documentation at #{@base_url}/docs

    ---
    LANG Universal Text Intelligence Platform
    #{@base_url}
    """
  end

  defp email_change_confirmation_text(user, new_email, confirmation_url) do
    """
    Confirm Your New Email

    Hello #{user.name},

    We received a request to change your email address from #{user.email} to #{new_email}.

    To confirm this change, please visit:

    #{confirmation_url}

    This confirmation link will expire in 24 hours.

    If you didn't request this email change, please contact our support team immediately at #{@support_email}

    ---
    LANG Universal Text Intelligence Platform
    #{@base_url}
    """
  end

  defp security_alert_email_text(user, action, details) do
    """
    Security Alert

    Hello #{user.name},

    We're writing to inform you about an important security event on your LANG account:

    #{format_security_action(action)}
    #{format_security_details_text(details)}

    If this was you, no further action is needed. If you don't recognize this activity, please:

    • Change your password immediately
    • Review your account settings at #{@base_url}/settings
    • Contact our support team at #{@support_email}

    ---
    LANG Universal Text Intelligence Platform
    #{@base_url}
    """
  end

  # Email Styling

  defp base_email_styles do
    """
    body {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
        line-height: 1.6;
        margin: 0;
        padding: 0;
        background-color: #f8fafc;
        color: #334155;
    }

    .container {
        max-width: 600px;
        margin: 0 auto;
        background-color: #ffffff;
        padding: 40px;
        border-radius: 8px;
        box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
    }

    .header {
        text-align: center;
        padding: 20px 0;
        background: linear-gradient(135deg, #4a9eff 0%, #0066ff 100%);
        margin-bottom: 40px;
    }

    .logo {
        font-size: 32px;
        font-weight: 300;
        color: white;
        text-decoration: none;
    }

    h1 {
        color: #1e293b;
        font-size: 28px;
        font-weight: 600;
        margin-bottom: 20px;
        text-align: center;
    }

    h3 {
        color: #475569;
        font-size: 20px;
        font-weight: 600;
        margin-top: 30px;
        margin-bottom: 15px;
    }

    p {
        margin-bottom: 20px;
        font-size: 16px;
        line-height: 1.6;
    }

    .button-container {
        text-align: center;
        margin: 30px 0;
    }

    .button {
        display: inline-block;
        padding: 14px 28px;
        background: linear-gradient(135deg, #4a9eff 0%, #0066ff 100%);
        color: white;
        text-decoration: none;
        border-radius: 6px;
        font-weight: 600;
        font-size: 16px;
        transition: transform 0.2s;
    }

    .button:hover {
        transform: translateY(-1px);
    }

    .link {
        word-break: break-all;
        background-color: #f1f5f9;
        padding: 10px;
        border-radius: 4px;
        font-family: monospace;
        font-size: 14px;
    }

    .features-preview {
        background-color: #f8fafc;
        padding: 20px;
        border-radius: 6px;
        margin: 30px 0;
    }

    .features-preview ul {
        margin: 10px 0;
        padding-left: 0;
    }

    .features-preview li {
        margin-bottom: 8px;
        list-style: none;
        font-size: 15px;
    }

    .security-notice, .security-alert {
        background-color: #fef2f2;
        border-left: 4px solid #ef4444;
        padding: 15px;
        margin: 20px 0;
        border-radius: 4px;
    }

    .getting-started {
        margin: 30px 0;
    }

    .feature-card {
        background-color: #f8fafc;
        padding: 15px;
        border-radius: 6px;
        margin-bottom: 15px;
    }

    .feature-card h4 {
        color: #1e293b;
        font-size: 16px;
        margin-bottom: 8px;
    }

    .subscription-info {
        background-color: #f0f9ff;
        border-left: 4px solid #0ea5e9;
        padding: 15px;
        margin: 20px 0;
        border-radius: 4px;
    }

    .subscription-info ul {
        margin: 10px 0;
        padding-left: 20px;
    }

    .subscription-info li {
        margin-bottom: 6px;
        font-size: 15px;
    }

    .footer {
        text-align: center;
        padding: 30px 20px;
        background-color: #1e293b;
        color: #94a3b8;
        font-size: 14px;
    }

    .footer a {
        color: #4a9eff;
        text-decoration: none;
    }
    """
  end

  defp email_header do
    """
    <div class="header">
        <a href="#{@base_url}" class="logo">LANG</a>
    </div>
    """
  end

  defp email_footer do
    """
    <div class="footer">
        <p>
            <strong>LANG Universal Text Intelligence Platform</strong><br>
            Transform any text into actionable intelligence
        </p>
        <p>
            <a href="#{@base_url}/unsubscribe">Unsubscribe</a> |
            <a href="#{@base_url}/privacy">Privacy Policy</a> |
            <a href="mailto:#{@support_email}">Support</a>
        </p>
        <p>© 2024 LANG Platform. All rights reserved.</p>
    </div>
    """
  end

  # Helper Functions

  defp format_security_action(action) do
    case action do
      :password_changed -> "Password Changed"
      :email_changed -> "Email Address Changed"
      :oauth_linked -> "OAuth Account Linked"
      :oauth_unlinked -> "OAuth Account Unlinked"
      :api_key_created -> "API Key Created"
      :api_key_revoked -> "API Key Revoked"
      :suspicious_login -> "Suspicious Login Attempt"
      _ -> "Account Activity"
    end
  end

  defp format_security_details(details) do
    timestamp = details[:timestamp] || DateTime.utc_now()
    ip_address = details[:ip_address] || "Unknown"
    user_agent = details[:user_agent] || "Unknown"

    """
    <p><strong>When:</strong> #{Calendar.strftime(timestamp, "%B %d, %Y at %I:%M %p UTC")}</p>
    <p><strong>IP Address:</strong> #{ip_address}</p>
    <p><strong>Device/Browser:</strong> #{user_agent}</p>
    """
  end

  defp format_security_details_text(details) do
    timestamp = details[:timestamp] || DateTime.utc_now()
    ip_address = details[:ip_address] || "Unknown"
    user_agent = details[:user_agent] || "Unknown"

    """
    When: #{Calendar.strftime(timestamp, "%B %d, %Y at %I:%M %p UTC")}
    IP Address: #{ip_address}
    Device/Browser: #{user_agent}
    """
  end
end
