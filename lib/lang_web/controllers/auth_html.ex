defmodule LangWeb.AuthHTML do
  @moduledoc """
  Authentication HTML templates for LANG Universal Text Intelligence Platform.

  Provides templates for login, registration, password reset, and other
  authentication-related functionality with proper design system integration.
  """

  use LangWeb, :html
  import LangWeb.AuthComponents

  embed_templates "auth_html/*"

  @doc """
  Renders the main authentication page with login/register forms.
  """
  attr :changeset, :any, required: true, doc: "Registration form changeset"
  attr :login_changeset, :any, required: true, doc: "Login form changeset"
  attr :page_title, :string, default: "Sign In - LANG"

  def show(assigns) do
    ~H"""
    <.auth_navbar />

    <.auth_container>
      <!-- Logo -->
      <div class="text-center">
        <div class="flex items-center justify-center gap-2 sm:gap-3 mb-4 sm:mb-6">
          <.auth_logo id="authLogo" />
          <span class="text-2xl sm:text-3xl font-light text-white">LANG</span>
        </div>
        <h2 class="mt-4 sm:mt-6 text-center text-2xl sm:text-3xl font-extrabold text-white">
          Welcome to LANG
        </h2>
        <p class="mt-2 text-center text-xs sm:text-sm text-gray-400">
          Universal Text Intelligence Platform
        </p>
      </div>
      
    <!-- Tab Navigation -->
      <div class="flex rounded-lg bg-gray-800 p-1">
        <a
          href="/auth"
          class={"flex-1 text-center py-2 px-4 rounded-md text-sm font-medium transition-all " <> if @mode != "register", do: "bg-gray-700 text-white", else: "text-gray-400 hover:text-white"}
        >
          Sign In
        </a>
        <a
          href="/auth?mode=register"
          class={"flex-1 text-center py-2 px-4 rounded-md text-sm font-medium transition-all " <> if @mode == "register", do: "bg-gray-700 text-white", else: "text-gray-400 hover:text-white"}
        >
          Sign Up
        </a>
      </div>
      
    <!-- Login Form -->
      <div id="login-form" class={"space-y-6 " <> if @mode == "register", do: "hidden", else: ""}>
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
                class="block w-full px-3 py-2 text-sm sm:text-base border border-gray-600 rounded-md shadow-sm bg-gray-800 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
              />
            </div>
            <div>
              <.input
                field={@login_changeset[:password]}
                type="password"
                label="Password"
                required
                class="block w-full px-3 py-2 text-sm sm:text-base border border-gray-600 rounded-md shadow-sm bg-gray-800 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
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
              class="group relative w-full flex justify-center py-3 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition-colors touch-manipulation"
            >
              Sign In
            </button>
          </div>
        </.form>
      </div>
      
    <!-- Registration Form -->
      <div id="register-form" class={"space-y-6 " <> if @mode != "register", do: "hidden", else: ""}>
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
                class="block w-full px-3 py-2 text-sm sm:text-base border border-gray-600 rounded-md shadow-sm bg-gray-800 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-purple-500 focus:border-purple-500"
              />
            </div>
            <div>
              <.input
                field={@changeset[:email]}
                type="email"
                label="Email address"
                required
                class="block w-full px-3 py-2 text-sm sm:text-base border border-gray-600 rounded-md shadow-sm bg-gray-800 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-purple-500 focus:border-purple-500"
              />
            </div>
            <div>
              <.input
                field={@changeset[:password]}
                type="password"
                label="Password"
                required
                class="block w-full px-3 py-2 text-sm sm:text-base border border-gray-600 rounded-md shadow-sm bg-gray-800 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-purple-500 focus:border-purple-500"
              />
            </div>
            <div>
              <.input
                field={@changeset[:password_confirmation]}
                type="password"
                label="Confirm Password"
                required
                class="block w-full px-3 py-2 text-sm sm:text-base border border-gray-600 rounded-md shadow-sm bg-gray-800 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-purple-500 focus:border-purple-500"
              />
            </div>
            <div>
              <.input
                field={@changeset[:organization_name]}
                type="text"
                label="Organization Name"
                required
                class="block w-full px-3 py-2 text-sm sm:text-base border border-gray-600 rounded-md shadow-sm bg-gray-800 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-purple-500 focus:border-purple-500"
              />
            </div>
          </div>

          <div>
            <button
              type="submit"
              class="group relative w-full flex justify-center py-3 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-purple-600 hover:bg-purple-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-purple-500 transition-colors touch-manipulation"
            >
              Sign Up
            </button>
          </div>
        </.form>
      </div>

      <.oauth_buttons />
    </.auth_container>
    """
  end

  @doc """
  Renders the forgot password page.
  """
  attr :page_title, :string, default: "Reset Password - LANG"

  def forgot_password(assigns) do
    ~H"""
    <.auth_navbar />

    <.auth_container>
      <!-- Logo and Header -->
      <div class="text-center">
        <div class="flex items-center justify-center gap-2 sm:gap-3 mb-4 sm:mb-6">
          <.auth_logo id="forgotLogo" />
          <span class="text-2xl sm:text-3xl font-light text-white">LANG</span>
        </div>
        <h2 class="mt-4 sm:mt-6 text-center text-2xl sm:text-3xl font-extrabold text-white">
          Forgot your password?
        </h2>
        <p class="mt-2 text-center text-xs sm:text-sm text-gray-400">
          Enter your email address and we'll send you a reset link
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
    </.auth_container>
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
    <.auth_navbar />

    <.auth_container>
      <!-- Logo -->
      <div class="text-center">
        <div class="flex items-center justify-center gap-2 sm:gap-3 mb-4 sm:mb-6">
          <.auth_logo id="resetLogo" />
          <span class="text-2xl sm:text-3xl font-light text-white">LANG</span>
        </div>
        <h2 class="mt-4 sm:mt-6 text-center text-2xl sm:text-3xl font-extrabold text-white">
          Set new password
        </h2>
        <p class="mt-2 text-center text-xs sm:text-sm text-gray-400">
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
              class="block w-full px-3 py-2 text-sm sm:text-base border border-gray-600 rounded-md shadow-sm bg-gray-800 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
            />
          </div>
          <div>
            <.input
              field={@changeset[:password_confirmation]}
              type="password"
              label="Confirm New Password"
              required
              class="block w-full px-3 py-2 text-sm sm:text-base border border-gray-600 rounded-md shadow-sm bg-gray-800 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
            />
          </div>
        </div>

        <div>
          <button
            type="submit"
            class="group relative w-full flex justify-center py-3 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition-colors touch-manipulation"
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
    </.auth_container>
    """
  end
end
