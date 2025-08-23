defmodule LangWeb.LandingLive do
  use LangWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(3000, self(), :cycle_use_case)
    end

    {:ok,
     assign(socket,
       demo_active: false,
       current_use_case: 0,
       use_cases: generate_use_cases()
     )}
  end

  @impl true
  def handle_event("start_demo", _params, socket) do
    {:noreply, assign(socket, demo_active: true)}
  end

  @impl true
  def handle_event("switch_use_case", %{"index" => index}, socket) do
    {:noreply, assign(socket, current_use_case: String.to_integer(index))}
  end

  @impl true
  def handle_info(:cycle_use_case, socket) do
    if socket.assigns.demo_active do
      next_case = rem(socket.assigns.current_use_case + 1, length(socket.assigns.use_cases))
      {:noreply, assign(socket, current_use_case: next_case)}
    else
      {:noreply, socket}
    end
  end

  defp generate_use_cases do
    [
      %{
        title: "Legal Contract Analysis",
        domain: "Legal Tech",
        icon: "⚖️",
        description: "AI lawyer analyzing contract clauses for risks and compliance",
        content: """
        EMPLOYMENT AGREEMENT

        Section 4.2: Non-Compete Clause
        Employee agrees not to engage in competing 
        business activities within 50 miles of Company 
        headquarters for a period of 24 months...

        Section 7.1: Intellectual Property
        All inventions, discoveries, and improvements 
        made by Employee during employment shall be...
        """,
        insights: [
          %{
            type: "risk",
            text: "Non-compete radius may be too broad for enforceability",
            confidence: 87
          },
          %{
            type: "suggestion",
            text: "Consider adding invention assignment exceptions",
            confidence: 92
          },
          %{
            type: "compliance",
            text: "Clause complies with California labor code section 925",
            confidence: 95
          }
        ],
        stats: %{clauses_analyzed: 47, risks_found: 3, compliance_score: "94%"}
      },
      %{
        title: "Recipe Optimization",
        domain: "Culinary AI",
        icon: "👨‍🍳",
        description: "Professional chef assistant optimizing recipes for nutrition and taste",
        content: """
        CHOCOLATE CHIP COOKIES

        Ingredients:
        - 2¼ cups all-purpose flour
        - 1 cup butter, softened  
        - ¾ cup brown sugar
        - ½ cup white sugar
        - 2 large eggs
        - 2 tsp vanilla extract
        - 1 tsp baking soda
        - 1 tsp salt
        - 2 cups chocolate chips
        """,
        insights: [
          %{
            type: "nutrition",
            text: "Reduce butter by 25% and add applesauce for lower calories",
            confidence: 89
          },
          %{type: "texture", text: "Chill dough 2 hours for chewier texture", confidence: 94},
          %{
            type: "flavor",
            text: "Add 1 tsp espresso powder to enhance chocolate flavor",
            confidence: 91
          }
        ],
        stats: %{calories_per_serving: 156, prep_time: "15 min", difficulty: "Easy"}
      },
      %{
        title: "Sales Email Optimization",
        domain: "Sales Intelligence",
        icon: "📧",
        description: "Sales team maximizing email response rates with AI-powered insights",
        content: """
        Subject: Quick question about your Q4 goals

        Hi Sarah,

        I noticed your company just raised Series B funding. 
        Congratulations! 

        I'm reaching out because we help fast-growing 
        SaaS companies like yours reduce customer churn 
        by up to 40% using predictive analytics.

        Would you have 15 minutes this week to discuss 
        how this might impact your retention metrics?

        Best,
        Mike
        """,
        insights: [
          %{
            type: "response_rate",
            text: "Personalized opener increases reply rate by 23%",
            confidence: 91
          },
          %{
            type: "timing",
            text: "Tuesday 10 AM optimal send time for this prospect",
            confidence: 86
          },
          %{
            type: "tone",
            text: "Casual tone matches prospect's communication style",
            confidence: 88
          }
        ],
        stats: %{
          predicted_response_rate: "34%",
          sentiment_score: "Positive",
          reading_time: "12 sec"
        }
      },
      %{
        title: "Medical Chart Analysis",
        domain: "Healthcare AI",
        icon: "🏥",
        description: "Clinical assistant identifying patterns and drug interactions",
        content: """
        PATIENT: Johnson, Robert (DOB: 1967-03-15)

        CURRENT MEDICATIONS:
        - Metformin 1000mg BID
        - Lisinopril 10mg daily
        - Atorvastatin 40mg daily

        RECENT LAB RESULTS:
        - HbA1c: 7.2% (elevated)
        - LDL: 145 mg/dL (high)
        - Creatinine: 1.4 mg/dL (borderline)

        SYMPTOMS: Fatigue, frequent urination
        """,
        insights: [
          %{
            type: "interaction",
            text: "No drug interactions detected in current regimen",
            confidence: 97
          },
          %{
            type: "adjustment",
            text: "Consider increasing Metformin to 1500mg BID",
            confidence: 84
          },
          %{
            type: "monitoring",
            text: "Creatinine levels require monthly monitoring",
            confidence: 93
          }
        ],
        stats: %{interactions_checked: 15, guidelines_verified: 8, risk_score: "Low"}
      }
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100" data-theme="dark">
      <!-- Navigation -->
      <nav class="navbar bg-base-100/80 backdrop-blur-sm border-b border-base-300 sticky top-0 z-50">
        <div class="navbar-start">
          <div class="text-xl font-bold bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent">
            LANG
          </div>
        </div>
        <div class="navbar-center hidden lg:flex">
          <ul class="menu menu-horizontal px-1 text-sm">
            <li><a class="hover:text-primary">Features</a></li>
            <li><a class="hover:text-primary">Documentation</a></li>
            <li><a class="hover:text-primary">Pricing</a></li>
          </ul>
        </div>
        <div class="navbar-end">
          <button class="btn btn-primary btn-sm">Request Beta</button>
        </div>
      </nav>
      
    <!-- Hero Section -->
      <section class="hero min-h-[90vh] bg-gradient-to-br from-base-100 via-base-200 to-base-300 relative">
        <div class="hero-content text-center max-w-7xl mx-auto px-6">
          <div class="grid lg:grid-cols-2 gap-16 items-center w-full">
            <!-- Left: Content -->
            <div class="text-left space-y-8">
              <div class="space-y-4">
                <h1 class="text-5xl lg:text-7xl font-bold leading-tight">
                  Universal Text
                  <span class="bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent">
                    Intelligence
                  </span>
                </h1>
                <p class="text-xl text-base-content/70 leading-relaxed max-w-lg">
                  From legal contracts to cooking recipes, sales emails to medical charts.
                  LANG turns any text into intelligent, actionable insights.
                </p>
              </div>

              <div class="flex flex-col sm:flex-row gap-4">
                <button
                  class="btn btn-primary btn-lg group"
                  phx-click="start_demo"
                >
                  <span>Try Live Demo</span>
                  <svg
                    class="w-5 h-5 ml-2 group-hover:translate-x-1 transition-transform"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M13 7l5 5m0 0l-5 5m5-5H6"
                    >
                    </path>
                  </svg>
                </button>
                <button class="btn btn-outline btn-lg">
                  <svg class="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 20 20">
                    <path
                      fill-rule="evenodd"
                      d="M10 0C4.477 0 0 4.484 0 10.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0110 4.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.203 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.942.359.31.678.921.678 1.856 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0020 10.017C20 4.484 15.522 0 10 0z"
                      clip-rule="evenodd"
                    >
                    </path>
                  </svg>
                  View on GitHub
                </button>
              </div>
              
    <!-- Stats -->
              <div class="grid grid-cols-4 gap-6 pt-8">
                <div class="stat p-0">
                  <div class="stat-value text-2xl text-primary">50+</div>
                  <div class="stat-desc">Text Formats</div>
                </div>
                <div class="stat p-0">
                  <div class="stat-value text-2xl text-secondary">∞</div>
                  <div class="stat-desc">Use Cases</div>
                </div>
                <div class="stat p-0">
                  <div class="stat-value text-2xl text-accent">Real-time</div>
                  <div class="stat-desc">Analysis</div>
                </div>
                <div class="stat p-0">
                  <div class="stat-value text-2xl text-info">Any</div>
                  <div class="stat-desc">Domain</div>
                </div>
              </div>
            </div>
            
    <!-- Right: Demo -->
            <div class="relative">
              <%= if @demo_active do %>
                <!-- Live Demo Window -->
                <% current_case = Enum.at(@use_cases, @current_use_case) %>
                <div class="mockup-window border border-base-300 bg-base-200 shadow-2xl">
                  <div class="bg-base-100 px-4 py-2 border-b border-base-300">
                    <div class="flex items-center justify-between">
                      <div class="flex items-center gap-2">
                        <div class="w-3 h-3 rounded-full bg-error"></div>
                        <div class="w-3 h-3 rounded-full bg-warning"></div>
                        <div class="w-3 h-3 rounded-full bg-success"></div>
                      </div>
                      <div class="text-sm font-mono text-base-content/60">
                        LANG Intelligence • {current_case.domain}
                      </div>
                      <div class="flex items-center gap-2">
                        <div class="w-2 h-2 rounded-full bg-success animate-pulse"></div>
                        <span class="text-xs text-success">Live</span>
                      </div>
                    </div>
                  </div>
                  
    <!-- Use Case Tabs -->
                  <div class="tabs tabs-lifted bg-base-200">
                    <%= for {use_case, index} <- Enum.with_index(@use_cases) do %>
                      <button
                        class={"tab tab-lifted text-xs #{if @current_use_case == index, do: "tab-active"}"}
                        phx-click="switch_use_case"
                        phx-value-index={index}
                      >
                        <span class="mr-1">{use_case.icon}</span>
                        <span class="hidden lg:inline">{use_case.title}</span>
                        <span class="lg:hidden">{use_case.domain}</span>
                      </button>
                    <% end %>
                  </div>
                  
    <!-- Demo Content -->
                  <div class="bg-base-100 p-6 min-h-[500px]">
                    <div class="grid grid-cols-2 gap-6 h-full">
                      <!-- Original Content -->
                      <div class="space-y-4">
                        <div class="flex items-center gap-2 mb-3">
                          <div class="text-2xl">{current_case.icon}</div>
                          <div>
                            <h4 class="font-semibold">{current_case.title}</h4>
                            <p class="text-sm text-base-content/70">{current_case.description}</p>
                          </div>
                        </div>

                        <div class="mockup-code bg-base-200 text-sm max-h-80 overflow-y-auto">
                          <pre class="text-xs leading-relaxed px-4 py-2"><code>{current_case.content}</code></pre>
                        </div>
                        
    <!-- Stats for this use case -->
                        <div class="grid grid-cols-3 gap-2 text-center">
                          <%= for {key, value} <- current_case.stats do %>
                            <div class="bg-base-200 rounded p-2">
                              <div class="text-sm font-bold text-primary">{value}</div>
                              <div class="text-xs text-base-content/60">
                                {key
                                |> Atom.to_string()
                                |> String.replace("_", " ")
                                |> String.capitalize()}
                              </div>
                            </div>
                          <% end %>
                        </div>
                      </div>
                      
    <!-- AI Insights -->
                      <div class="space-y-4">
                        <h4 class="font-semibold text-sm text-base-content/70 flex items-center gap-2">
                          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              stroke-width="2"
                              d="M13 10V3L4 14h7v7l9-11h-7z"
                            >
                            </path>
                          </svg>
                          LANG Intelligence
                        </h4>

                        <div class="space-y-3">
                          <%= for insight <- current_case.insights do %>
                            <div class="card card-compact bg-base-200 border border-base-300">
                              <div class="card-body">
                                <div class="flex items-start gap-3">
                                  <%= case insight.type do %>
                                    <% "risk" -> %>
                                      <div class="badge badge-error badge-sm">⚠️ Risk</div>
                                    <% "suggestion" -> %>
                                      <div class="badge badge-primary badge-sm">💡 Suggestion</div>
                                    <% "compliance" -> %>
                                      <div class="badge badge-success badge-sm">✅ Compliance</div>
                                    <% "nutrition" -> %>
                                      <div class="badge badge-accent badge-sm">🥗 Nutrition</div>
                                    <% "texture" -> %>
                                      <div class="badge badge-secondary badge-sm">🍪 Texture</div>
                                    <% "flavor" -> %>
                                      <div class="badge badge-warning badge-sm">😋 Flavor</div>
                                    <% "response_rate" -> %>
                                      <div class="badge badge-info badge-sm">📈 Response</div>
                                    <% "timing" -> %>
                                      <div class="badge badge-primary badge-sm">⏰ Timing</div>
                                    <% "tone" -> %>
                                      <div class="badge badge-secondary badge-sm">🎯 Tone</div>
                                    <% "interaction" -> %>
                                      <div class="badge badge-success badge-sm">🔬 Safety</div>
                                    <% "adjustment" -> %>
                                      <div class="badge badge-warning badge-sm">💊 Dosage</div>
                                    <% "monitoring" -> %>
                                      <div class="badge badge-error badge-sm">👁️ Monitor</div>
                                    <% _ -> %>
                                      <div class="badge badge-neutral badge-sm">ℹ️ Info</div>
                                  <% end %>
                                  <div class="flex-1">
                                    <div class="text-sm">{insight.text}</div>
                                    <div class="text-xs text-base-content/60 mt-1">
                                      {insight.confidence}% confidence
                                    </div>
                                  </div>
                                </div>
                              </div>
                            </div>
                          <% end %>
                        </div>
                        
    <!-- Auto-cycle indicator -->
                        <div class="text-center pt-4">
                          <div class="text-xs text-base-content/50 flex items-center justify-center gap-2">
                            <div class="w-2 h-2 rounded-full bg-primary animate-pulse"></div>
                            Auto-cycling through examples
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              <% else %>
                <!-- Demo Placeholder -->
                <div class="mockup-window border border-base-300 bg-base-200 shadow-2xl">
                  <div class="bg-base-100 flex justify-center items-center py-24">
                    <div class="text-center space-y-4">
                      <div class="text-6xl mb-4">🧠</div>
                      <div>
                        <h4 class="font-semibold text-lg">Experience Universal Intelligence</h4>
                        <p class="text-base-content/60">
                          See LANG analyze contracts, recipes, emails, and medical charts
                        </p>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </section>
      
    <!-- Features Section -->
      <section class="py-24 bg-base-200">
        <div class="max-w-7xl mx-auto px-6">
          <div class="text-center mb-16">
            <h2 class="text-4xl font-bold mb-4">Why LANG?</h2>
            <p class="text-xl text-base-content/70 max-w-2xl mx-auto">
              Bridge the gap between simple text and complex systems with universal intelligence
            </p>
          </div>

          <div class="grid lg:grid-cols-3 gap-8">
            <!-- Feature 1 -->
            <div class="card bg-base-100 shadow-lg border border-base-300 hover:shadow-xl transition-shadow">
              <div class="card-body">
                <div class="text-4xl mb-4">🌳</div>
                <h3 class="card-title text-xl mb-3">Universal Language Server</h3>
                <p class="text-base-content/70 mb-4">
                  One LSP server for ALL text formats. Legal docs, recipes, emails, code -
                  get intelligent completions and analysis in any editor.
                </p>
                <div class="flex flex-wrap gap-2">
                  <div class="badge badge-primary badge-outline">LSP</div>
                  <div class="badge badge-primary badge-outline">Multi-format</div>
                  <div class="badge badge-primary badge-outline">Any Editor</div>
                </div>
              </div>
            </div>
            
    <!-- Feature 2 -->
            <div class="card bg-base-100 shadow-lg border border-base-300 hover:shadow-xl transition-shadow">
              <div class="card-body">
                <div class="text-4xl mb-4">🧠</div>
                <h3 class="card-title text-xl mb-3">Domain-Aware Intelligence</h3>
                <p class="text-base-content/70 mb-4">
                  Context-aware AI that understands legal clauses, recipe chemistry,
                  sales psychology, and medical protocols - not just syntax.
                </p>
                <div class="flex flex-wrap gap-2">
                  <div class="badge badge-secondary badge-outline">Context-aware</div>
                  <div class="badge badge-secondary badge-outline">Domain-specific</div>
                  <div class="badge badge-secondary badge-outline">AI-powered</div>
                </div>
              </div>
            </div>
            
    <!-- Feature 3 -->
            <div class="card bg-base-100 shadow-lg border border-base-300 hover:shadow-xl transition-shadow">
              <div class="card-body">
                <div class="text-4xl mb-4">⚡</div>
                <h3 class="card-title text-xl mb-3">Real-time Analysis</h3>
                <p class="text-base-content/70 mb-4">
                  Instant feedback as you type. Risk analysis in contracts,
                  nutritional optimization in recipes, sentiment in emails.
                </p>
                <div class="flex flex-wrap gap-2">
                  <div class="badge badge-accent badge-outline">Real-time</div>
                  <div class="badge badge-accent badge-outline">As-you-type</div>
                  <div class="badge badge-accent badge-outline">Instant</div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>
      
    <!-- CTA Section -->
      <section class="py-24 bg-gradient-to-br from-primary/10 via-base-100 to-secondary/10">
        <div class="max-w-4xl mx-auto text-center px-6">
          <h2 class="text-4xl lg:text-5xl font-bold mb-6">
            Ready to Make Your Text
            <span class="bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent">
              Intelligent?
            </span>
          </h2>
          <p class="text-xl text-base-content/70 mb-8 max-w-2xl mx-auto">
            Join the beta and experience universal text intelligence today.
            Transform how you work with any structured content.
          </p>

          <div class="flex flex-col sm:flex-row gap-4 justify-center items-center">
            <button class="btn btn-primary btn-lg">
              <span>Request Beta Access</span>
              <svg class="w-5 h-5 ml-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M13 7l5 5m0 0l-5 5m5-5H6"
                />
              </svg>
            </button>
          </div>
        </div>
      </section>
    </div>
    """
  end
end
