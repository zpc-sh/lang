defmodule LangWeb.DesignSystemLive do
  use LangWeb, :live_view
  import LangWeb.NavbarComponent

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "LANG™ Design System 2025")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={assigns[:current_user]}
      current_scope={assigns[:current_scope]}
    >
      <div class="design-system pt-0">
        
    <!-- Hero Section -->
        <section class="hero">
          <div class="matrix-bg" phx-hook="MatrixRain" id="matrix-bg"></div>
          <div class="grid-pattern"></div>

          <div class="hero-content">
            <svg class="hero-logo" viewBox="0 0 300 300" xmlns="http://www.w3.org/2000/svg">
              <defs>
                <linearGradient id="heroGrad1" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" style="stop-color:#4a9eff;stop-opacity:1">
                    <animate
                      attributeName="stop-color"
                      values="#4a9eff;#00ff88;#ff00ff;#4a9eff"
                      dur="10s"
                      repeatCount="indefinite"
                    />
                  </stop>
                  <stop offset="100%" style="stop-color:#0066ff;stop-opacity:1">
                    <animate
                      attributeName="stop-color"
                      values="#0066ff;#00ffff;#00ff88;#0066ff"
                      dur="10s"
                      repeatCount="indefinite"
                    />
                  </stop>
                </linearGradient>
                <filter id="heroGlow">
                  <feGaussianBlur stdDeviation="8" result="coloredBlur" />
                  <feMerge>
                    <feMergeNode in="coloredBlur" />
                    <feMergeNode in="SourceGraphic" />
                  </feMerge>
                </filter>
              </defs>

              <g filter="url(#heroGlow)">
                <circle
                  cx="150"
                  cy="150"
                  r="140"
                  fill="none"
                  stroke="url(#heroGrad1)"
                  stroke-width="1"
                  opacity="0.3"
                >
                  <animate attributeName="r" values="140;145;140" dur="4s" repeatCount="indefinite" />
                </circle>
                <circle
                  cx="150"
                  cy="150"
                  r="120"
                  fill="none"
                  stroke="url(#heroGrad1)"
                  stroke-width="2"
                  opacity="0.5"
                >
                  <animate attributeName="r" values="120;115;120" dur="3s" repeatCount="indefinite" />
                </circle>
                <circle
                  cx="150"
                  cy="150"
                  r="100"
                  fill="none"
                  stroke="url(#heroGrad1)"
                  stroke-width="3"
                  opacity="0.7"
                >
                  <animate attributeName="r" values="100;105;100" dur="2s" repeatCount="indefinite" />
                </circle>

                <path
                  d="M 90 80 L 60 150 L 90 220"
                  stroke="url(#heroGrad1)"
                  stroke-width="8"
                  fill="none"
                  stroke-linecap="round"
                />

                <path
                  d="M 100 150 Q 125 130, 150 150 T 200 150"
                  stroke="url(#heroGrad1)"
                  stroke-width="7"
                  fill="none"
                  stroke-linecap="round"
                />

                <path
                  d="M 210 80 L 240 150 L 210 220"
                  stroke="url(#heroGrad1)"
                  stroke-width="8"
                  fill="none"
                  stroke-linecap="round"
                />
              </g>
            </svg>

            <h1 class="hero-title">LANG™ 2025</h1>
            <p class="hero-tagline">Universal Text Intelligence</p>
            <p class="hero-description">
              A consciousness infrastructure for AI systems. LANG extends LSP and Tree-sitter beyond code to provide semantic understanding and intelligent editing for ANY structured text format.
            </p>
            <div class="hero-cta">
              <a href="#design" class="btn btn-primary">Explore Design System</a>
              <a href="https://github.com/nocsi/lang" class="btn btn-secondary">View on GitHub</a>
            </div>
          </div>
        </section>
        
    <!-- Logo Showcase -->
        <section id="identity" class="section">
          <div class="section-header">
            <span class="section-label">01</span>
            <h2 class="section-title">Brand Identity</h2>
            <p class="section-subtitle">The visual foundation of universal text intelligence</p>
          </div>

          <div class="logo-showcase">
            <.logo_card
              title="Primary Logo"
              description="Main brand mark with consciousness rings"
              meta={[{"Format", "SVG"}, {"Usage", "Digital"}, {"Min Size", "32px"}]}
            />
            <.logo_card
              title="Monogram"
              description="Simplified mark for compact spaces"
              meta={[{"Format", "SVG"}, {"Usage", "Icons"}, {"Min Size", "16px"}]}
            />
            <.logo_card
              title="Wordmark"
              description="Typography-focused brand expression"
              meta={[{"Format", "SVG"}, {"Usage", "Headers"}, {"Min Size", "24px"}]}
            />
          </div>
        </section>
        
    <!-- Color System -->
        <section id="colors" class="section">
          <div class="section-header">
            <span class="section-label">02</span>
            <h2 class="section-title">Color Intelligence</h2>
            <p class="section-subtitle">Semantic colors that communicate meaning and state</p>
          </div>

          <div class="color-grid">
            <.color_section title="NOCSI Foundation" colors={nocsi_colors()} />
            <.color_section title="LANG Primary" colors={lang_primary_colors()} />
            <.color_section title="Semantic Intelligence" colors={semantic_colors()} />
            <.color_section title="System States" colors={state_colors()} />
          </div>
        </section>
        
    <!-- Typography -->
        <section id="typography" class="section">
          <div class="section-header">
            <span class="section-label">03</span>
            <h2 class="section-title">Typography Scale</h2>
            <p class="section-subtitle">Hierarchical text system for all communication</p>
          </div>

          <div class="type-showcase">
            <.type_specimen label="Display" class="type-display" text="Universal Intelligence" />
            <.type_specimen label="Heading 1" class="type-h1" text="System Architecture" />
            <.type_specimen label="Heading 2" class="type-h2" text="Component Library" />
            <.type_specimen label="Heading 3" class="type-h3" text="Design Tokens" />
            <.type_specimen
              label="Body Large"
              class="type-body-lg"
              text="This is the primary body text used for important descriptions and content."
            />
            <.type_specimen
              label="Body Regular"
              class="type-body"
              text="This is the standard body text used throughout the interface."
            />
            <.type_specimen
              label="Caption"
              class="type-caption"
              text="This is caption text used for metadata and secondary information."
            />
            <.type_specimen
              label="Code"
              class="type-code"
              text="document ⟨~⟩ Parser() ▷ analyze() ⇒ result"
            />
          </div>
        </section>
        
    <!-- Components -->
        <section id="components" class="section">
          <div class="section-header">
            <span class="section-label">04</span>
            <h2 class="section-title">Component Library</h2>
            <p class="section-subtitle">Reusable interface elements with semantic meaning</p>
          </div>

          <div class="component-showcase">
            <.component_preview
              title="Buttons"
              description="Primary, secondary, and semantic action triggers"
            >
              <div class="flex gap-4 flex-wrap">
                <button class="btn btn-primary">Primary Action</button>
                <button class="btn btn-secondary">Secondary</button>
                <button class="btn btn-parse">Parse</button>
                <button class="btn btn-semantic">Semantic</button>
                <button class="btn btn-transform">Transform</button>
              </div>
            </.component_preview>

            <.component_preview
              title="Status Indicators"
              description="System state communication"
            >
              <div class="flex gap-4 flex-wrap">
                <.status_badge status="processing" text="Processing" />
                <.status_badge status="success" text="Complete" />
                <.status_badge status="error" text="Error" />
                <.status_badge status="warning" text="Warning" />
              </div>
            </.component_preview>

            <.component_preview
              title="Intelligence Cards"
              description="Content containers with semantic meaning"
            >
              <div class="grid gap-4">
                <.intelligence_card
                  type="parse"
                  title="Parse Analysis"
                  description="Structural breakdown and tokenization complete"
                  progress={85}
                />
                <.intelligence_card
                  type="semantic"
                  title="Semantic Understanding"
                  description="Contextual meaning and relationships identified"
                  progress={92}
                />
              </div>
            </.component_preview>
          </div>
        </section>
        
    <!-- Code Examples -->
        <section id="code" class="section">
          <div class="section-header">
            <span class="section-label">05</span>
            <h2 class="section-title">Code Integration</h2>
            <p class="section-subtitle">How to implement LANG design tokens in your projects</p>
          </div>

          <div class="code-showcase">
            <.code_example
              title="CSS Custom Properties"
              language="css"
              code={css_example()}
            />
            <.code_example
              title="Phoenix Components"
              language="elixir"
              code={elixir_example()}
            />
            <.code_example
              title="Tailwind Config"
              language="javascript"
              code={tailwind_example()}
            />
          </div>
        </section>
        
    <!-- Footer -->
        <footer class="footer">
          <div class="footer-content">
            <div class="footer-logo">
              <svg width="32" height="32" viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">
                <defs>
                  <linearGradient id="footerGradient" x1="0%" y1="0%" x2="100%" y2="100%">
                    <stop offset="0%" style="stop-color:#4a9eff;stop-opacity:1" />
                    <stop offset="100%" style="stop-color:#0066ff;stop-opacity:1" />
                  </linearGradient>
                </defs>
                <path
                  d="M 35 35 L 25 60 L 35 85"
                  stroke="url(#footerGradient)"
                  stroke-width="3"
                  fill="none"
                  stroke-linecap="round"
                />
                <path
                  d="M 40 60 Q 50 52, 60 60 T 80 60"
                  stroke="url(#footerGradient)"
                  stroke-width="2.5"
                  fill="none"
                  stroke-linecap="round"
                />
                <path
                  d="M 85 35 L 95 60 L 85 85"
                  stroke="url(#footerGradient)"
                  stroke-width="3"
                  fill="none"
                  stroke-linecap="round"
                />
              </svg>
            </div>
            <p class="footer-text">LANG™ 2025 - Universal Text Intelligence</p>
            <p class="footer-copyright">© 2025 NOCSI. All rights reserved.</p>
          </div>
        </footer>
      </div>
    </Layouts.app>
    """
  end

  # Component helpers
  attr :variant, :string, required: true
  attr :title, :string, required: true

  def logo_card(assigns) do
    ~H"""
    <div class="logo-card">
      <div class="logo-display">
        <svg class="logo-svg" viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <linearGradient id={@title <> "Gradient"} x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" style="stop-color:#4a9eff;stop-opacity:1" />
              <stop offset="100%" style="stop-color:#0066ff;stop-opacity:1" />
            </linearGradient>
          </defs>
          <path
            d="M 35 35 L 25 60 L 35 85"
            stroke={"url(#" <> @title <> "Gradient)"}
            stroke-width="3"
            fill="none"
            stroke-linecap="round"
          />
          <path
            d="M 40 60 Q 50 52, 60 60 T 80 60"
            stroke={"url(#" <> @title <> "Gradient)"}
            stroke-width="2.5"
            fill="none"
            stroke-linecap="round"
          />
          <path
            d="M 85 35 L 95 60 L 85 85"
            stroke={"url(#" <> @title <> "Gradient)"}
            stroke-width="3"
            fill="none"
            stroke-linecap="round"
          />
        </svg>
      </div>
      <div class="logo-info">
        <h3>{@title}</h3>
        <p>{@description}</p>
      </div>
      <div class="logo-meta">
        <%= for {label, value} <- @meta do %>
          <div class="meta-item">
            <span class="meta-label">{label}</span>
            <span class="meta-value">{value}</span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :colors, :list, required: true

  def color_section(assigns) do
    ~H"""
    <div class="color-section">
      <h3 class="color-section-title">{@title}</h3>
      <div class="color-cards">
        <%= for color <- @colors do %>
          <.color_card {color} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :hex, :string, required: true
  attr :class, :string, required: true

  def color_card(assigns) do
    ~H"""
    <div class="color-card">
      <div class="color-sample" style={"background: #{@hex}"}></div>
      <div class="color-info">
        <div class="color-name">{@name}</div>
        <div class="color-hex">{@hex}</div>
        <%= if @variants && length(@variants) > 0 do %>
          <div class="color-variants">
            <%= for variant <- @variants do %>
              <div class="color-variant" style={"background: #{variant}"}></div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :text, :string, required: true
  attr :class, :string, required: true

  def type_specimen(assigns) do
    ~H"""
    <div class="type-specimen">
      <div class="type-label">
        <span class="type-label-text">{@label}</span>
        <div class="type-label-line"></div>
      </div>
      <div class={"type-sample #{@class}"}>{@text}</div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true
  slot :inner_block, required: true

  def component_preview(assigns) do
    ~H"""
    <div class="component-card">
      <div class="component-preview">
        {render_slot(@inner_block)}
      </div>
      <h3 class="component-title">{@title}</h3>
      <p class="component-description">{@description}</p>
    </div>
    """
  end

  attr :status, :string, required: true
  attr :text, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <div class={"status-badge status-#{@status}"}>
      <div class="status-indicator"></div>
      <span>{@text}</span>
    </div>
    """
  end

  attr :type, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :features, :list, required: true

  def intelligence_card(assigns) do
    ~H"""
    <div class={"intelligence-card intelligence-#{@type}"}>
      <div class="card-header">
        <h4>{@title}</h4>
        <div class="progress-circle">
          <span>{@progress}%</span>
        </div>
      </div>
      <p>{@description}</p>
      <div class="progress-bar">
        <div class="progress-fill" style={"width: #{@progress}%"}></div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :code, :string, required: true
  attr :language, :string, default: "elixir"

  def code_example(assigns) do
    ~H"""
    <div class="code-example">
      <div class="code-header">
        <span class="code-lang">{@language}</span>
        <div class="code-actions">
          <div class="code-dot red"></div>
          <div class="code-dot yellow"></div>
          <div class="code-dot green"></div>
        </div>
      </div>
      <div class="code-body">
        <pre><code phx-no-curly-interpolation><%= @code %></code></pre>
      </div>
    </div>
    """
  end

  # Color definitions
  defp nocsi_colors do
    [
      %{name: "Void", hex: "#000000", variants: []},
      %{name: "Deep", hex: "#020202", variants: []},
      %{name: "Dark", hex: "#0a0a0a", variants: []},
      %{name: "Carbon", hex: "#111111", variants: []},
      %{name: "Graphite", hex: "#1a1a1a", variants: []}
    ]
  end

  defp lang_primary_colors do
    [
      %{name: "Primary", hex: "#4a9eff", variants: ["#6eb3ff", "#0066ff", "#0044cc", "#002266"]},
      %{name: "Primary Dark", hex: "#0066ff", variants: []},
      %{name: "Primary Glow", hex: "#6eb3ff", variants: []},
      %{name: "Primary Deep", hex: "#0044cc", variants: []},
      %{name: "Primary Void", hex: "#002266", variants: []}
    ]
  end

  defp semantic_colors do
    [
      %{name: "Parse", hex: "#00ff88", variants: ["#33ffaa", "#00cc66"]},
      %{name: "Semantic", hex: "#ff00ff", variants: ["#ff66ff", "#cc00cc"]},
      %{name: "Transform", hex: "#00ffff", variants: ["#66ffff", "#00cccc"]}
    ]
  end

  defp state_colors do
    [
      %{name: "Error", hex: "#ff0066", variants: ["#ff3388"]},
      %{name: "Warning", hex: "#ffaa00", variants: ["#ffcc33"]},
      %{name: "Success", hex: "#00ff66", variants: []},
      %{name: "Info", hex: "#00aaff", variants: []}
    ]
  end

  # Code examples
  defp css_example do
    """
    :root {
      /* NOCSI Brand Colors */
      --nocsi-void: #000000;
      --nocsi-carbon: #111111;
      --nocsi-graphite: #1a1a1a;

      /* LANG Primary Spectrum */
      --lang-primary: #4a9eff;
      --lang-primary-dark: #0066ff;
      --lang-primary-glow: #6eb3ff;

      /* Semantic Intelligence Colors */
      --lang-parse: #00ff88;
      --lang-semantic: #ff00ff;
      --lang-transform: #00ffff;

      /* Gradients */
      --lang-gradient-primary: linear-gradient(135deg, #4a9eff 0%, #0066ff 100%);
      --lang-gradient-aurora: linear-gradient(135deg, #4a9eff 0%, #00ff88 33%, #ff00ff 66%, #00ffff 100%);
    }
    """
  end

  defp elixir_example do
    """
    def intelligence_card(assigns) do
      ~H\"\"\"
      <div class={"intelligence-card intelligence-#{@type}"}>
        <div class="card-header">
          <h4>{@title}</h4>
          <div class="progress-circle">
            <span>{@progress}%</span>
          </div>
        </div>
        <p>{@description}</p>
        <div class="progress-bar">
          <div class="progress-fill" style={"width: #{@progress}%"}></div>
        </div>
      </div>
      \"\"\"
    end
    """
  end

  defp tailwind_example do
    """
    module.exports = {
      theme: {
        extend: {
          colors: {
            'nocsi': {
              'void': '#000000',
              'carbon': '#111111',
              'graphite': '#1a1a1a',
            },
            'lang': {
              'primary': '#4a9eff',
              'parse': '#00ff88',
              'semantic': '#ff00ff',
              'transform': '#00ffff',
            }
          }
        }
      }
    }
    """
  end
end
