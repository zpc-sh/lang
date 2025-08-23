defmodule LangWeb.AuthHTML do
  @moduledoc """
  Authentication HTML templates for LANG Universal Text Intelligence Platform.

  Provides templates for login, registration, password reset, and other
  authentication-related functionality with proper design system integration.
  """

  use LangWeb, :html

  embed_templates "auth_html/*"

  @doc """
  Renders the main authentication page with login/register forms.
  """
  attr :changeset, :any, required: true, doc: "Registration form changeset"
  attr :login_changeset, :any, required: true, doc: "Login form changeset"
  attr :page_title, :string, default: "Sign In - LANG"

  def show(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-950 flex items-center justify-center py-12 px-4 sm:px-6 lg:px-8">
      <div class="max-w-md w-full space-y-8">
        <!-- Logo -->
        <div class="text-center">
          <div class="lang-logo text-4xl font-bold bg-gradient-to-r from-blue-400 via-purple-500 to-blue-600 bg-clip-text text-transparent">
            LANG
          </div>
          <h2 class="mt-6 text-center text-3xl font-extrabold text-white">
            Sign in to your account
          </h2>
          <p class="mt-2 text-center text-sm text-gray-400">
            Welcome to the Universal Text Intelligence Platform
          </p>
        </div>
        
    <!-- Login Form -->
        <div id="login-form" class="space-y-6">
          <.form
            for={@login_changeset}
            id="login-form-element"
            action="/auth/login"
            method="post"
            class="space-y-6"
          >
            <div class="space-y-4">
              <div>
                <.input
                  field={@login_changeset[:email]}
                  type="email"
                  label="Email address"
                  required
                  class="block w-full px-3 py-2 border border-gray-600 rounded-md shadow-sm bg-gray-800 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                />
              </div>
              <div>
                <.input
                  field={@login_changeset[:password]}
                  type="password"
                  label="Password"
                  required
                  class="block w-full px-3 py-2 border border-gray-600 rounded-md shadow-sm bg-gray-800 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                />
              </div>
            </div>

            <div class="flex items-center justify-between">
              <div class="text-sm">
                <a
                  href="/auth/forgot-password"
                  class="font-medium text-blue-400 hover:text-blue-300 transition-colors"
                >
                  Forgot your password?
                </a>
              </div>
            </div>

            <div>
              <button
                type="submit"
                class="group relative w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition-colors"
              >
                Sign in
              </button>
            </div>
          </.form>
        </div>
        
    <!-- Registration Form -->
        <div id="register-form" class="space-y-6 mt-8">
          <div class="text-center">
            <p class="text-sm text-gray-400">
              Don't have an account?
            </p>
          </div>

          <.form
            for={@changeset}
            id="registration-form"
            action="/auth/register"
            method="post"
            class="space-y-6"
          >
            <div class="space-y-4">
              <div>
                <.input
                  field={@changeset[:name]}
                  type="text"
                  label="Full Name"
                  required
                  class="block w-full px-3 py-2 border border-gray-600 rounded-md shadow-sm bg-gray-800 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-purple-500 focus:border-purple-500"
                />
              </div>
              <div>
                <.input
                  field={@changeset[:email]}
                  type="email"
                  label="Email address"
                  required
                  class="block w-full px-3 py-2 border border-gray-600 rounded-md shadow-sm bg-gray-800 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-purple-500 focus:border-purple-500"
                />
              </div>
              <div>
                <.input
                  field={@changeset[:password]}
                  type="password"
                  label="Password"
                  required
                  class="block w-full px-3 py-2 border border-gray-600 rounded-md shadow-sm bg-gray-800 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-purple-500 focus:border-purple-500"
                />
              </div>
              <div>
                <.input
                  field={@changeset[:password_confirmation]}
                  type="password"
                  label="Confirm Password"
                  required
                  class="block w-full px-3 py-2 border border-gray-600 rounded-md shadow-sm bg-gray-800 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-purple-500 focus:border-purple-500"
                />
              </div>
              <div>
                <.input
                  field={@changeset[:organization_name]}
                  type="text"
                  label="Organization Name"
                  required
                  class="block w-full px-3 py-2 border border-gray-600 rounded-md shadow-sm bg-gray-800 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-purple-500 focus:border-purple-500"
                />
              </div>
            </div>

            <div>
              <button
                type="submit"
                class="group relative w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-purple-600 hover:bg-purple-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-purple-500 transition-colors"
              >
                Create Account
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the forgot password page.
  """
  attr :page_title, :string, default: "Reset Password - LANG"

  def forgot_password(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-950 flex items-center justify-center py-12 px-4 sm:px-6 lg:px-8">
      <div class="max-w-md w-full space-y-8">
        <div class="text-center">
          <div class="lang-logo text-4xl font-bold bg-gradient-to-r from-blue-400 via-purple-500 to-blue-600 bg-clip-text text-transparent">
            LANG
          </div>
          <h2 class="mt-6 text-center text-3xl font-extrabold text-white">
            Reset your password
          </h2>
          <p class="mt-2 text-center text-sm text-gray-400">
            Enter your email address and we'll send you a link to reset your password.
          </p>
        </div>

        <form action="/auth/forgot-password" method="post" class="space-y-6">
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
          <div>
            <label for="email" class="block text-sm font-medium text-gray-300 mb-1">
              Email address
            </label>
            <input
              id="email"
              name="user[email]"
              type="email"
              autocomplete="email"
              required
              class="block w-full px-3 py-2 border border-gray-600 rounded-md shadow-sm bg-gray-800 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
              placeholder="Enter your email"
            />
          </div>

          <div>
            <button
              type="submit"
              class="group relative w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition-colors"
            >
              Send reset link
            </button>
          </div>

          <div class="text-center">
            <a
              href="/auth"
              class="font-medium text-blue-400 hover:text-blue-300 transition-colors"
            >
              Back to sign in
            </a>
          </div>
        </form>
      </div>
    </div>
    """
  end

  @doc """
  Renders the reset password page with token.
  """
  attr :user, :any, required: true, doc: "User to reset password for"
  attr :token, :string, required: true, doc: "Reset token"
  attr :changeset, :any, required: true, doc: "Password reset changeset"
  attr :page_title, :string, default: "Reset Password - LANG"

  def reset_password(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-950 flex items-center justify-center py-12 px-4 sm:px-6 lg:px-8">
      <div class="max-w-md w-full space-y-8">
        <div class="text-center">
          <div class="lang-logo text-4xl font-bold bg-gradient-to-r from-blue-400 via-purple-500 to-blue-600 bg-clip-text text-transparent">
            LANG
          </div>
          <h2 class="mt-6 text-center text-3xl font-extrabold text-white">
            Set new password
          </h2>
          <p class="mt-2 text-center text-sm text-gray-400">
            Enter your new password below.
          </p>
        </div>

        <.form
          for={@changeset}
          action={"/auth/reset-password/" <> @token}
          method="post"
          class="space-y-6"
        >
          <div class="space-y-4">
            <div>
              <.input
                field={@changeset[:password]}
                type="password"
                label="New Password"
                required
                class="block w-full px-3 py-2 border border-gray-600 rounded-md shadow-sm bg-gray-800 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
              />
            </div>
            <div>
              <.input
                field={@changeset[:password_confirmation]}
                type="password"
                label="Confirm New Password"
                required
                class="block w-full px-3 py-2 border border-gray-600 rounded-md shadow-sm bg-gray-800 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
              />
            </div>
          </div>

          <div>
            <button
              type="submit"
              class="group relative w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition-colors"
            >
              Update password
            </button>
          </div>
        </.form>

        <div class="text-center">
          <a
            href="/auth"
            class="font-medium text-blue-400 hover:text-blue-300 transition-colors"
          >
            Back to sign in
          </a>
        </div>
      </div>
    </div>
    """
  end
end
