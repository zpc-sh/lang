defmodule LangWeb.AuthComponents do
  @moduledoc """
  Shared components for authentication pages.

  Provides consistent navigation and UI elements across all auth-related pages.
  """

  use Phoenix.Component
  import Phoenix.HTML

  @doc """
  Renders a consistent navigation bar for authentication pages.
  """
  def auth_navbar(assigns) do
    ~H"""
    <!-- Auth Page Navbar -->
    <nav class="fixed top-0 left-0 right-0 z-50 bg-gray-900/80 backdrop-blur-md border-b border-gray-800">
      <div class="max-w-7xl mx-auto px-6 sm:px-8 lg:px-12">
        <div class="flex items-center justify-between h-16">
          <!-- Logo -->
          <div class="flex items-center">
            <a href="/" class="flex items-center gap-3">
              <svg class="w-8 h-8" viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">
                <defs>
                  <linearGradient id="authNavLogo" x1="0%" y1="0%" x2="100%" y2="100%">
                    <stop offset="0%" style="stop-color:#4a9eff;stop-opacity:1" />
                    <stop offset="100%" style="stop-color:#0066ff;stop-opacity:1" />
                  </linearGradient>
                </defs>
                <path
                  d="M 35 35 L 25 60 L 35 85"
                  stroke="url(#authNavLogo)"
                  stroke-width="3"
                  fill="none"
                  stroke-linecap="round"
                />
                <path
                  d="M 40 60 Q 50 52, 60 60 T 80 60"
                  stroke="url(#authNavLogo)"
                  stroke-width="2.5"
                  fill="none"
                  stroke-linecap="round"
                />
                <path
                  d="M 85 35 L 95 60 L 85 85"
                  stroke="url(#authNavLogo)"
                  stroke-width="3"
                  fill="none"
                  stroke-linecap="round"
                />
              </svg>
              <span class="text-xl font-light text-white">LANG</span>
            </a>
          </div>
          
    <!-- Desktop Navigation -->
          <div class="hidden md:flex items-center space-x-8">
            <a href="/analyze" class="text-gray-300 hover:text-white transition-colors duration-200">
              Text Analysis
            </a>
            <a href="/docs" class="text-gray-300 hover:text-white transition-colors duration-200">
              Documentation
            </a>
            <a
              href="/api-portal"
              class="text-gray-300 hover:text-white transition-colors duration-200"
            >
              API
            </a>
            <div class="h-4 w-px bg-gray-600"></div>
            <a
              href="/"
              class="text-blue-400 hover:text-blue-300 transition-colors duration-200 flex items-center gap-2"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M10 19l-7-7m0 0l7-7m-7 7h18"
                />
              </svg>
              Back to Home
            </a>
          </div>
          
    <!-- Mobile menu button -->
          <div class="md:hidden">
            <button
              type="button"
              class="text-gray-400 hover:text-white focus:outline-none focus:text-white transition-colors duration-200"
              onclick="toggleAuthMobileMenu()"
              aria-label="Toggle mobile menu"
            >
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4 6h16M4 12h16M4 18h16"
                />
              </svg>
            </button>
          </div>
        </div>
        
    <!-- Mobile Navigation Menu -->
        <div id="auth-mobile-menu" class="hidden md:hidden pb-4 border-t border-gray-700 mt-4 pt-4">
          <div class="space-y-2">
            <a
              href="/analyze"
              class="block px-3 py-2 text-gray-300 hover:text-white hover:bg-gray-800 rounded-md transition-colors duration-200"
            >
              Text Analysis
            </a>
            <a
              href="/docs"
              class="block px-3 py-2 text-gray-300 hover:text-white hover:bg-gray-800 rounded-md transition-colors duration-200"
            >
              Documentation
            </a>
            <a
              href="/api-portal"
              class="block px-3 py-2 text-gray-300 hover:text-white hover:bg-gray-800 rounded-md transition-colors duration-200"
            >
              API
            </a>
            <div class="border-t border-gray-700 my-2"></div>
            <a
              href="/"
              class="block px-3 py-2 text-blue-400 hover:text-blue-300 hover:bg-gray-800 rounded-md transition-colors duration-200 flex items-center gap-2"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M10 19l-7-7m0 0l7-7m-7 7h18"
                />
              </svg>
              Back to Home
            </a>
          </div>
        </div>
      </div>
    </nav>

    <script>
      function toggleAuthMobileMenu() {
        const menu = document.getElementById('auth-mobile-menu');
        if (menu) {
          menu.classList.toggle('hidden');
        }
      }
    </script>
    """
  end

  @doc """
  Renders the auth page container with consistent styling.
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def auth_container(assigns) do
    ~H"""
    <div class={"min-h-screen bg-gray-950 flex items-center justify-center py-8 px-3 sm:py-12 sm:px-6 lg:px-8 pt-20 sm:pt-24 " <> @class}>
      <div class="max-w-md w-full space-y-6 sm:space-y-8">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Renders the LANG logo for auth pages.
  """
  attr :class, :string, default: "w-10 h-10 sm:w-12 sm:h-12"
  attr :id, :string, default: "authPageLogo"

  def auth_logo(assigns) do
    ~H"""
    <svg
      class={@class}
      viewBox="0 0 120 120"
      xmlns="http://www.w3.org/2000/svg"
    >
      <defs>
        <linearGradient id={@id} x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" style="stop-color:#4a9eff;stop-opacity:1" />
          <stop offset="100%" style="stop-color:#0066ff;stop-opacity:1" />
        </linearGradient>
      </defs>
      <path
        d="M 35 35 L 25 60 L 35 85"
        stroke={"url(##{@id})"}
        stroke-width="3"
        fill="none"
        stroke-linecap="round"
      />
      <path
        d="M 40 60 Q 50 52, 60 60 T 80 60"
        stroke={"url(##{@id})"}
        stroke-width="2.5"
        fill="none"
        stroke-linecap="round"
      />
      <path
        d="M 85 35 L 95 60 L 85 85"
        stroke={"url(##{@id})"}
        stroke-width="3"
        fill="none"
        stroke-linecap="round"
      />
    </svg>
    """
  end

  @doc """
  Renders OAuth provider buttons in a grid layout.
  """
  def oauth_buttons(assigns) do
    ~H"""
    <!-- OAuth Authentication Section -->
    <div class="mt-6">
      <div class="relative">
        <div class="absolute inset-0 flex items-center">
          <div class="w-full border-t border-gray-600"></div>
        </div>
        <div class="relative flex justify-center text-sm">
          <span class="px-2 bg-gray-900 text-gray-400">Or continue with</span>
        </div>
      </div>

      <div class="mt-6 grid grid-cols-3 gap-3">
        <!-- GitHub OAuth -->
        <a
          href="/auth/github"
          class="w-full inline-flex justify-center py-2 px-4 border border-gray-600 rounded-md shadow-sm bg-gray-800 text-sm font-medium text-gray-300 hover:bg-gray-700 hover:border-gray-500 transition-colors touch-manipulation"
          title="Sign in with GitHub"
        >
          <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true">
            <path
              fill-rule="evenodd"
              d="M10 0C4.477 0 0 4.484 0 10.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0110 4.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.203 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.942.359.31.678.921.678 1.856 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0020 10.017C20 4.484 15.522 0 10 0z"
              clip-rule="evenodd"
            />
          </svg>
        </a>
        
    <!-- Google OAuth -->
        <a
          href="/auth/google"
          class="w-full inline-flex justify-center py-2 px-4 border border-gray-600 rounded-md shadow-sm bg-gray-800 text-sm font-medium text-gray-300 hover:bg-gray-700 hover:border-gray-500 transition-colors touch-manipulation"
          title="Sign in with Google"
        >
          <svg class="w-5 h-5" viewBox="0 0 24 24">
            <path
              fill="#4285F4"
              d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
            />
            <path
              fill="#34A853"
              d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
            />
            <path
              fill="#FBBC05"
              d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
            />
            <path
              fill="#EA4335"
              d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
            />
          </svg>
        </a>
        
    <!-- Apple OAuth -->
        <a
          href="/auth/apple"
          class="w-full inline-flex justify-center py-2 px-4 border border-gray-600 rounded-md shadow-sm bg-gray-800 text-sm font-medium text-gray-300 hover:bg-gray-700 hover:border-gray-500 transition-colors touch-manipulation"
          title="Sign in with Apple"
        >
          <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true">
            <path d="M15.312 11.424c-.047-3.25 2.656-4.812 2.766-4.875-1.516-2.203-3.859-2.5-4.687-2.531-1.969-.203-3.844 1.171-4.844 1.171-.984 0-2.531-1.125-4.156-1.094-2.125.031-4.094 1.25-5.188 3.156C-2.969 11.578.984 18.484 4.297 22.297c.844 0 1.531-.156 2.344-.406.734-.203 1.531-.406 2.531-.406 1 0 1.781.203 2.531.406.812.25 1.5.406 2.344.406 3.312-3.812 7.265-10.719 5.265-10.87z" />
            <path d="M12.281 4.766c.703-.859 1.187-2.062 1.062-3.266-1.016.047-2.25.687-2.984 1.547-.656.766-1.234 2.008-1.078 3.188 1.141.09 2.305-.578 3-1.469z" />
          </svg>
        </a>
      </div>
    </div>
    """
  end
end
