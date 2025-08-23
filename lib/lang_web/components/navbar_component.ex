defmodule LangWeb.NavbarComponent do
  @moduledoc """
  Unified navigation bar component for LANG Universal Text Intelligence Platform.

  Provides consistent navigation across all pages with proper authentication state,
  mobile responsiveness, and accessibility features.
  """

  use Phoenix.Component
  import Phoenix.HTML

  @doc """
  Renders the main navigation bar for the platform.

  Adapts based on user authentication status and current page context.
  """
  attr :current_user, :any, default: nil, doc: "Current authenticated user"

  attr :current_page, :atom,
    default: :home,
    doc: "Current page identifier for highlighting active links"

  attr :class, :string, default: "", doc: "Additional CSS classes"

  attr :variant, :atom,
    default: :default,
    values: [:default, :transparent, :solid],
    doc: "Navbar style variant"

  def navbar(assigns) do
    ~H"""
    <nav class={[
      "fixed top-0 left-0 right-0 z-50 border-b transition-all duration-200",
      navbar_bg_class(@variant),
      @class
    ]}>
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex items-center justify-between h-16">
          <!-- Logo -->
          <div class="flex items-center">
            <.logo_link />
          </div>
          
    <!-- Desktop Navigation -->
          <div class="hidden md:flex items-center space-x-8">
            <.nav_links current_page={@current_page} current_user={@current_user} />
          </div>
          
    <!-- Right Side Actions -->
          <div class="hidden md:flex items-center space-x-4">
            <.right_actions current_user={@current_user} />
          </div>
          
    <!-- Mobile menu button -->
          <div class="md:hidden">
            <button
              type="button"
              class="text-gray-400 hover:text-white focus:outline-none focus:text-white transition-colors duration-200"
              onclick="toggleMobileNav()"
              aria-label="Toggle mobile menu"
              aria-expanded="false"
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
        <div id="mobile-nav" class="hidden md:hidden border-t border-gray-700 mt-4 pt-4 pb-4">
          <div class="space-y-2">
            <.mobile_nav_links current_page={@current_page} current_user={@current_user} />
            <div class="border-t border-gray-700 my-4 pt-4">
              <.mobile_right_actions current_user={@current_user} />
            </div>
          </div>
        </div>
      </div>
    </nav>

    <script>
      function toggleMobileNav() {
        const menu = document.getElementById('mobile-nav');
        const button = document.querySelector('[aria-label="Toggle mobile menu"]');

        if (menu && button) {
          const isHidden = menu.classList.contains('hidden');
          menu.classList.toggle('hidden');
          button.setAttribute('aria-expanded', isHidden ? 'true' : 'false');
        }
      }

      // Close mobile menu when clicking outside
      document.addEventListener('click', function(event) {
        const menu = document.getElementById('mobile-nav');
        const button = document.querySelector('[aria-label="Toggle mobile menu"]');

        if (menu && !menu.classList.contains('hidden') &&
            !menu.contains(event.target) &&
            !button.contains(event.target)) {
          menu.classList.add('hidden');
          button.setAttribute('aria-expanded', 'false');
        }
      });
    </script>
    """
  end

  # Logo component
  defp logo_link(assigns) do
    ~H"""
    <a href="/" class="flex items-center gap-2 sm:gap-3 hover:opacity-80 transition-opacity">
      <svg
        class="w-6 h-6 sm:w-8 sm:h-8"
        viewBox="0 0 120 120"
        xmlns="http://www.w3.org/2000/svg"
      >
        <defs>
          <linearGradient id="navbarLogo" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" style="stop-color:#4a9eff;stop-opacity:1" />
            <stop offset="100%" style="stop-color:#0066ff;stop-opacity:1" />
          </linearGradient>
        </defs>
        <path
          d="M 35 35 L 25 60 L 35 85"
          stroke="url(#navbarLogo)"
          stroke-width="3"
          fill="none"
          stroke-linecap="round"
        />
        <path
          d="M 40 60 Q 50 52, 60 60 T 80 60"
          stroke="url(#navbarLogo)"
          stroke-width="2.5"
          fill="none"
          stroke-linecap="round"
        />
        <path
          d="M 85 35 L 95 60 L 85 85"
          stroke="url(#navbarLogo)"
          stroke-width="3"
          fill="none"
          stroke-linecap="round"
        />
      </svg>
      <span class="text-lg sm:text-xl font-light text-white">LANG</span>
    </a>
    """
  end

  # Desktop navigation links
  defp nav_links(assigns) do
    ~H"""
    <.nav_link href="/analyze" current_page={@current_page} page_key={:analyze}>
      Text Analysis
    </.nav_link>

    <.nav_link href="/docs" current_page={@current_page} page_key={:docs}>
      Documentation
    </.nav_link>

    <%= if @current_user do %>
      <.nav_link href="/dashboard" current_page={@current_page} page_key={:dashboard}>
        Dashboard
      </.nav_link>

      <.nav_link href="/api-portal" current_page={@current_page} page_key={:api_portal}>
        API
      </.nav_link>
    <% else %>
      <.nav_link href="/api-portal" current_page={@current_page} page_key={:api_portal}>
        API
      </.nav_link>
    <% end %>
    """
  end

  # Individual navigation link
  attr :href, :string, required: true
  attr :current_page, :atom, required: true
  attr :page_key, :atom, required: true
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <a
      href={@href}
      class={[
        "text-sm font-medium transition-colors duration-200",
        nav_link_classes(@current_page == @page_key)
      ]}
    >
      {render_slot(@inner_block)}
    </a>
    """
  end

  # Right side actions (auth buttons, user menu)
  defp right_actions(assigns) do
    ~H"""
    <%= if @current_user do %>
      <!-- User Menu -->
      <div class="relative">
        <button
          type="button"
          class="flex items-center gap-2 text-gray-300 hover:text-white transition-colors duration-200"
          onclick="toggleUserMenu()"
          aria-label="User menu"
        >
          <%= if @current_user.avatar_url do %>
            <img
              src={@current_user.avatar_url}
              alt={@current_user.name}
              class="w-8 h-8 rounded-full ring-2 ring-gray-600"
            />
          <% else %>
            <div class="w-8 h-8 rounded-full bg-gradient-to-br from-blue-500 to-blue-600 flex items-center justify-center text-white text-sm font-medium">
              {String.first(@current_user.name) |> String.upcase()}
            </div>
          <% end %>
          <span class="hidden lg:block text-sm">
            {String.split(@current_user.name) |> List.first()}
          </span>
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
          </svg>
        </button>
        
    <!-- Dropdown Menu -->
        <div
          id="user-menu"
          class="hidden absolute right-0 mt-2 w-48 bg-gray-800 rounded-md shadow-lg border border-gray-700 py-1 z-50"
        >
          <a
            href="/dashboard"
            class="block px-4 py-2 text-sm text-gray-300 hover:text-white hover:bg-gray-700 transition-colors"
          >
            <div class="flex items-center gap-2">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2H5a2 2 0 00-2-2z"
                />
              </svg>
              Dashboard
            </div>
          </a>
          <a
            href="/settings"
            class="block px-4 py-2 text-sm text-gray-300 hover:text-white hover:bg-gray-700 transition-colors"
          >
            <div class="flex items-center gap-2">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
                />
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                />
              </svg>
              Settings
            </div>
          </a>
          <div class="border-t border-gray-700 my-1"></div>
          <form action="/auth/logout" method="delete" class="block">
            <input type="hidden" name="_csrf_token" value={Phoenix.HTML.Tag.csrf_token_value()} />
            <button
              type="submit"
              class="w-full text-left px-4 py-2 text-sm text-gray-300 hover:text-white hover:bg-gray-700 transition-colors"
            >
              <div class="flex items-center gap-2">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"
                  />
                </svg>
                Sign Out
              </div>
            </button>
          </form>
        </div>
      </div>

      <script>
        function toggleUserMenu() {
          const menu = document.getElementById('user-menu');
          if (menu) {
            menu.classList.toggle('hidden');
          }
        }

        // Close user menu when clicking outside
        document.addEventListener('click', function(event) {
          const menu = document.getElementById('user-menu');
          const button = document.querySelector('[aria-label="User menu"]');

          if (menu && !menu.classList.contains('hidden') &&
              !menu.contains(event.target) &&
              !button.contains(event.target)) {
            menu.classList.add('hidden');
          }
        });
      </script>
    <% else %>
      <!-- Auth Buttons -->
      <div class="flex items-center space-x-4">
        <a
          href="/auth"
          class="text-gray-300 hover:text-white text-sm font-medium transition-colors duration-200"
        >
          Sign In
        </a>
        <a
          href="/auth?mode=register"
          class="bg-gradient-to-r from-blue-500 to-blue-600 hover:from-blue-600 hover:to-blue-700 text-white px-4 py-2 rounded-md text-sm font-medium transition-all duration-200 hover:shadow-lg hover:shadow-blue-500/25"
        >
          Get Started
        </a>
      </div>
    <% end %>
    """
  end

  # Mobile navigation links
  defp mobile_nav_links(assigns) do
    ~H"""
    <.mobile_nav_link href="/analyze" current_page={@current_page} page_key={:analyze}>
      Text Analysis
    </.mobile_nav_link>

    <.mobile_nav_link href="/docs" current_page={@current_page} page_key={:docs}>
      Documentation
    </.mobile_nav_link>

    <%= if @current_user do %>
      <.mobile_nav_link href="/dashboard" current_page={@current_page} page_key={:dashboard}>
        Dashboard
      </.mobile_nav_link>
    <% end %>

    <.mobile_nav_link href="/api-portal" current_page={@current_page} page_key={:api_portal}>
      API
    </.mobile_nav_link>
    """
  end

  # Individual mobile navigation link
  attr :href, :string, required: true
  attr :current_page, :atom, required: true
  attr :page_key, :atom, required: true
  slot :inner_block, required: true

  defp mobile_nav_link(assigns) do
    ~H"""
    <a
      href={@href}
      class={[
        "block px-3 py-2 rounded-md text-base font-medium transition-colors duration-200",
        mobile_nav_link_classes(@current_page == @page_key)
      ]}
      onclick="toggleMobileNav()"
    >
      {render_slot(@inner_block)}
    </a>
    """
  end

  # Mobile right actions
  defp mobile_right_actions(assigns) do
    ~H"""
    <%= if @current_user do %>
      <div class="space-y-2">
        <!-- User Info -->
        <div class="px-3 py-2">
          <div class="flex items-center gap-3">
            <%= if @current_user.avatar_url do %>
              <img
                src={@current_user.avatar_url}
                alt={@current_user.name}
                class="w-10 h-10 rounded-full ring-2 ring-gray-600"
              />
            <% else %>
              <div class="w-10 h-10 rounded-full bg-gradient-to-br from-blue-500 to-blue-600 flex items-center justify-center text-white text-base font-medium">
                {String.first(@current_user.name) |> String.upcase()}
              </div>
            <% end %>
            <div>
              <div class="text-sm font-medium text-white">{@current_user.name}</div>
              <div class="text-xs text-gray-400">{@current_user.email}</div>
            </div>
          </div>
        </div>
        
    <!-- Mobile User Menu Items -->
        <a
          href="/settings"
          class="block px-3 py-2 rounded-md text-gray-300 hover:text-white hover:bg-gray-800 transition-colors"
          onclick="toggleMobileNav()"
        >
          <div class="flex items-center gap-2">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
              />
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
              />
            </svg>
            Settings
          </div>
        </a>

        <form action="/auth/logout" method="delete" class="block">
          <input type="hidden" name="_csrf_token" value={Phoenix.HTML.Tag.csrf_token_value()} />
          <button
            type="submit"
            class="w-full text-left px-3 py-2 rounded-md text-gray-300 hover:text-white hover:bg-gray-800 transition-colors"
          >
            <div class="flex items-center gap-2">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"
                />
              </svg>
              Sign Out
            </div>
          </button>
        </form>
      </div>
    <% else %>
      <div class="space-y-2">
        <a
          href="/auth"
          class="block px-3 py-2 rounded-md text-gray-300 hover:text-white hover:bg-gray-800 transition-colors text-center"
          onclick="toggleMobileNav()"
        >
          Sign In
        </a>
        <a
          href="/auth?mode=register"
          class="block px-3 py-2 rounded-md bg-gradient-to-r from-blue-500 to-blue-600 hover:from-blue-600 hover:to-blue-700 text-white font-medium transition-all duration-200 text-center"
          onclick="toggleMobileNav()"
        >
          Get Started
        </a>
      </div>
    <% end %>
    """
  end

  # Helper functions for styling
  defp navbar_bg_class(variant) do
    case variant do
      :transparent -> "bg-transparent"
      :solid -> "bg-gray-900 border-gray-800"
      :default -> "bg-gray-900/80 backdrop-blur-md border-gray-800"
    end
  end

  defp nav_link_classes(is_current) do
    if is_current do
      "text-white border-b-2 border-blue-500"
    else
      "text-gray-300 hover:text-white border-b-2 border-transparent hover:border-gray-600"
    end
  end

  defp mobile_nav_link_classes(is_current) do
    if is_current do
      "text-white bg-gray-800"
    else
      "text-gray-300 hover:text-white hover:bg-gray-800"
    end
  end
end
