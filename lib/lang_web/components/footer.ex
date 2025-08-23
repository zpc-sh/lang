defmodule LangWeb.Components.Footer do
  @moduledoc """
  Footer component for LANG Universal Text Intelligence Platform.

  Provides consistent footer with navigation links, social media links,
  and company information across the application.
  """

  use Phoenix.Component

  @doc """
  Renders the LANG footer with navigation links and branding.

  ## Examples

      <Footer.render />
  """
  def footer(assigns) do
    ~H"""
    <footer class="bg-gray-950 border-t border-gray-800 pt-16 pb-8 px-6 sm:px-12 lg:px-16">
      <div class="max-w-7xl mx-auto">
        <div class="grid md:grid-cols-4 gap-8 mb-12">
          <!-- Company -->
          <div>
            <div class="flex items-center gap-3 mb-4">
              <svg class="w-8 h-8" viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">
                <defs>
                  <linearGradient id="footerLogo" x1="0%" y1="0%" x2="100%" y2="100%">
                    <stop offset="0%" style="stop-color:#4a9eff;stop-opacity:1" />
                    <stop offset="100%" style="stop-color:#0066ff;stop-opacity:1" />
                  </linearGradient>
                </defs>
                <path
                  d="M 35 35 L 25 60 L 35 85"
                  stroke="url(#footerLogo)"
                  stroke-width="3"
                  fill="none"
                  stroke-linecap="round"
                />
                <path
                  d="M 40 60 Q 50 52, 60 60 T 80 60"
                  stroke="url(#footerLogo)"
                  stroke-width="2.5"
                  fill="none"
                  stroke-linecap="round"
                />
                <path
                  d="M 85 35 L 95 60 L 85 85"
                  stroke="url(#footerLogo)"
                  stroke-width="3"
                  fill="none"
                  stroke-linecap="round"
                />
              </svg>
              <span class="text-xl font-light">LANG</span>
            </div>
            <p class="text-gray-400 text-sm mb-4">
              Universal Text Intelligence Platform. Transform any text into actionable insights.
            </p>
            <div class="flex gap-4">
              <a href="https://github.com/lang" class="text-gray-500 hover:text-gray-300">
                <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z" />
                </svg>
              </a>
              <a href="https://twitter.com/lang" class="text-gray-500 hover:text-gray-300">
                <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M23 3a10.9 10.9 0 01-3.14 1.53 4.48 4.48 0 00-7.86 3v1A10.66 10.66 0 013 4s-4 9 5 13a11.64 11.64 0 01-7 2c9 5 20 0 20-11.5a4.5 4.5 0 00-.08-.83A7.72 7.72 0 0023 3z" />
                </svg>
              </a>
            </div>
          </div>
          
    <!-- Product -->
          <div>
            <h4 class="font-semibold mb-4">Product</h4>
            <ul class="space-y-2 text-sm">
              <li><a href="/#features" class="text-gray-400 hover:text-gray-200">Features</a></li>
              <li><a href="/#pricing" class="text-gray-400 hover:text-gray-200">Pricing</a></li>
              <li>
                <a href="/api-portal" class="text-gray-400 hover:text-gray-200">API Reference</a>
              </li>
              <li>
                <a href="/integrations" class="text-gray-400 hover:text-gray-200">Integrations</a>
              </li>
            </ul>
          </div>
          
    <!-- Resources -->
          <div>
            <h4 class="font-semibold mb-4">Resources</h4>
            <ul class="space-y-2 text-sm">
              <li><a href="/docs" class="text-gray-400 hover:text-gray-200">Documentation</a></li>
              <li><a href="/blog" class="text-gray-400 hover:text-gray-200">Blog</a></li>
              <li><a href="/tutorials" class="text-gray-400 hover:text-gray-200">Tutorials</a></li>
              <li><a href="/community" class="text-gray-400 hover:text-gray-200">Community</a></li>
            </ul>
          </div>
          
    <!-- Company -->
          <div>
            <h4 class="font-semibold mb-4">Company</h4>
            <ul class="space-y-2 text-sm">
              <li><a href="/about" class="text-gray-400 hover:text-gray-200">About</a></li>
              <li><a href="/contact" class="text-gray-400 hover:text-gray-200">Contact</a></li>
              <li>
                <a href="/privacy" class="text-gray-400 hover:text-gray-200">Privacy Policy</a>
              </li>
            </ul>
          </div>
        </div>

        <div class="border-t border-gray-800 pt-8 flex flex-col md:flex-row justify-between items-center text-sm text-gray-500">
          <p>&copy; 2025 NOCSI. All rights reserved.</p>
          <p>Built with ❤️ using Elixir, Phoenix, and Rust</p>
        </div>
      </div>
    </footer>
    """
  end
end
