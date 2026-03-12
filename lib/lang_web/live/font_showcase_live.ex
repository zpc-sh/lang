defmodule LangWeb.FontShowcaseLive do
  @moduledoc """
  LANG Mono - A Font That Understands Code
  Interactive showcase for the LANG Mono programming font
  """
  use LangWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "LANG Mono - A Font That Understands Code")
     |> assign(:input_text, "document <~> Parser() |> analyze() => result")
     |> assign(:show_ligature_details, false)
     |> assign(:selected_ligature, nil)
     |> assign(:animation_speed, "normal")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={assigns[:current_user]}
      current_scope={assigns[:current_scope]}
    >
      <!-- Hero Section -->
      <section class="relative overflow-hidden">
        <div class="absolute inset-0">
          <div class="absolute inset-0 bg-gradient-to-br from-blue-900/20 via-transparent to-purple-900/20">
          </div>
        </div>

        <div class="relative px-6 py-24 sm:px-12 lg:px-16">
          <div class="max-w-7xl mx-auto text-center">
            <h1 class="text-6xl md:text-8xl font-thin tracking-tight mb-6">
              LANG
              <span class="font-light bg-gradient-to-r from-blue-400 via-purple-400 to-blue-400 bg-clip-text text-transparent animate-gradient">
                Mono
              </span>
            </h1>

            <p class="text-xl md:text-2xl text-gray-400 tracking-widest uppercase mb-12">
              A Font That Understands Code
            </p>
            
    <!-- Animated Logo Display -->
            <div class="flex justify-center items-center gap-8 mb-16">
              <span class="text-4xl font-mono text-gray-500 animate-pulse">&lt;~&gt;</span>
              <svg class="w-8 h-8 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M13 7l5 5m0 0l-5 5m5-5H6"
                >
                </path>
              </svg>
              <div class="relative">
                <span class="text-6xl font-mono text-white">⟨~⟩</span>
                <div class="absolute -inset-4 bg-blue-500/20 blur-xl animate-pulse"></div>
              </div>
            </div>

            <p class="text-lg text-gray-400 max-w-3xl mx-auto leading-relaxed">
              The first programming font designed specifically for semantic parsing and universal text intelligence.
              Every ligature tells a story about data flow, transformation, and meaning.
            </p>
          </div>
        </div>
      </section>
      
    <!-- Interactive Demo -->
      <section class="px-6 py-20 sm:px-12 lg:px-16 bg-gray-900/50">
        <div class="max-w-7xl mx-auto">
          <h2 class="text-3xl font-light text-gray-300 mb-12 text-center">Try It Live</h2>

          <div class="bg-gray-950 border border-gray-800 rounded-xl p-8">
            <form phx-change="update_text">
              <textarea
                name="text"
                class="w-full bg-gray-900 text-white font-mono text-lg p-4 rounded-lg border border-gray-700 focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 transition-all"
                rows="3"
                placeholder="Type your code here..."
              ><%= @input_text %></textarea>
            </form>

            <div class="mt-6 p-6 bg-gray-900 rounded-lg border border-gray-800">
              <div class="text-sm text-gray-500 uppercase tracking-wider mb-2">
                Rendered with LANG Mono
              </div>
              <div class="font-mono text-2xl text-white leading-relaxed">
                {render_with_ligatures(@input_text)}
              </div>
            </div>
          </div>
        </div>
      </section>
      
    <!-- Ligature Showcase Grid -->
      <section class="px-6 py-20 sm:px-12 lg:px-16">
        <div class="max-w-7xl mx-auto">
          <h2 class="text-3xl font-light text-gray-300 mb-12 text-center">Semantic Ligatures</h2>

          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
            <%= for {from, to, name, description} <- ligatures() do %>
              <div
                class="group bg-gray-900 border border-gray-800 rounded-lg p-6 hover:border-blue-600 transition-all cursor-pointer hover:shadow-lg hover:shadow-blue-600/10"
                phx-click="show_ligature"
                phx-value-from={from}
                phx-value-to={to}
                phx-value-description={description}
              >
                <div class="flex items-center justify-between mb-3">
                  <span class="font-mono text-xl text-gray-500">{from}</span>
                  <span class="text-gray-600">→</span>
                  <span class="font-mono text-3xl text-blue-400 group-hover:text-blue-300 transition-colors">
                    {to}
                  </span>
                </div>
                <div class="text-xs text-gray-600 uppercase tracking-wider mb-1">{name}</div>
                <div class="text-sm text-gray-500">{description}</div>
              </div>
            <% end %>
          </div>
        </div>
      </section>
      
    <!-- Code Examples -->
      <section class="px-6 py-20 sm:px-12 lg:px-16 bg-gray-900/50">
        <div class="max-w-7xl mx-auto">
          <h2 class="text-3xl font-light text-gray-300 mb-12 text-center">In Action</h2>

          <div class="grid md:grid-cols-2 gap-8">
            <!-- Elixir Example -->
            <div class="bg-gray-950 border border-gray-800 rounded-xl overflow-hidden">
              <div class="bg-gray-900 px-6 py-3 border-b border-gray-800">
                <span class="text-purple-400 font-medium">Elixir + LANG</span>
              </div>
              <pre class="p-6 text-sm leading-relaxed overflow-x-auto"><code class="language-elixir"><span class="text-purple-400">defmodule</span> <span class="text-yellow-300">Lang.Parser</span> <span class="text-purple-400">do</span>
    <span class="text-gray-500"># Parse with semantic awareness</span>
    <span class="text-purple-400">def</span> <span class="text-blue-300">analyze</span>(document) <span class="text-purple-400">do</span>
    document
    <span class="text-gray-300">|></span> validate()      <span class="text-gray-500"># |> → ▷</span>
    <span class="text-gray-300">|></span> tokenize()
    <span class="text-gray-300">~></span> semantics()    <span class="text-gray-500"># ~> → ⟿</span>
    <span class="text-gray-300">=></span> format_output  <span class="text-gray-500"># => → ⇒</span>
    <span class="text-purple-400">end</span>

    <span class="text-purple-400">def</span> <span class="text-blue-300">parse</span>(text <span class="text-gray-300">::</span> <span class="text-green-400">String.t</span>) <span class="text-purple-400">do</span>  <span class="text-gray-500"># :: → ∷</span>
    text <span class="text-gray-300">&lt;~&gt;</span> Parser.new()       <span class="text-gray-500"># &lt;~> → ⟨~⟩</span>
    <span class="text-purple-400">end</span>
    <span class="text-purple-400">end</span></code></pre>
            </div>
            
    <!-- Python Example -->
            <div class="bg-gray-950 border border-gray-800 rounded-xl overflow-hidden">
              <div class="bg-gray-900 px-6 py-3 border-b border-gray-800">
                <span class="text-blue-400 font-medium">Python + LANG</span>
              </div>
              <pre class="p-6 text-sm leading-relaxed overflow-x-auto" phx-no-curly-interpolation><code class="language-python"><span class="text-purple-400">def</span> <span class="text-blue-300">analyze_document</span>(text: str) <span class="text-gray-300">-></span> SemanticTree:
    <span class="text-gray-500"># Universal text intelligence</span>
    <span class="text-purple-400">if</span> text <span class="text-gray-300">!=</span> <span class="text-purple-400">None</span>:      <span class="text-gray-500"># != → ≠</span>
        result = (
            lang.parse(text)
            <span class="text-gray-300">|></span> transform()  <span class="text-gray-500"># |> → ▷</span>
            <span class="text-gray-300">~></span> analyze()    <span class="text-gray-500"># ~> → ⟿</span>
        )

        <span class="text-purple-400">return</span> result <span class="text-gray-300">=></span> {  <span class="text-gray-500"># => → ⇒</span>
            <span class="text-orange-300">'ast'</span>: result.ast,
            <span class="text-orange-300">'semantic'</span>: <span class="text-gray-300">[[</span>result<span class="text-gray-300">]]</span>  <span class="text-gray-500"># [[]] → ⟦⟧</span>
        }</code></pre>
            </div>
          </div>
        </div>
      </section>
      
    <!-- Features -->
      <section class="px-6 py-20 sm:px-12 lg:px-16">
        <div class="max-w-7xl mx-auto">
          <h2 class="text-3xl font-light text-gray-300 mb-12 text-center">Why LANG Mono?</h2>

          <div class="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
            <div class="bg-gray-900 border border-gray-800 rounded-xl p-8 hover:border-gray-700 transition-all">
              <div class="text-4xl mb-4">🧠</div>
              <h3 class="text-xl font-medium mb-3">Semantic Awareness</h3>
              <p class="text-gray-400">
                Ligatures represent actual parsing and flow concepts. Each transformation has meaning beyond aesthetics.
              </p>
            </div>

            <div class="bg-gray-900 border border-gray-800 rounded-xl p-8 hover:border-gray-700 transition-all">
              <div class="text-4xl mb-4">⟨~⟩</div>
              <h3 class="text-xl font-medium mb-3">LANG Native</h3>
              <p class="text-gray-400">
                The &lt;~&gt; sequence becomes our iconic logo. Built specifically for LANG's universal text intelligence.
              </p>
            </div>

            <div class="bg-gray-900 border border-gray-800 rounded-xl p-8 hover:border-gray-700 transition-all">
              <div class="text-4xl mb-4">🌳</div>
              <h3 class="text-xl font-medium mb-3">Parse Tree Ready</h3>
              <p class="text-gray-400">
                Enhanced box drawing and tree characters designed for beautiful AST visualization.
              </p>
            </div>

            <div class="bg-gray-900 border border-gray-800 rounded-xl p-8 hover:border-gray-700 transition-all">
              <div class="text-4xl mb-4">👁️</div>
              <h3 class="text-xl font-medium mb-3">Crystal Clarity</h3>
              <p class="text-gray-400">
                Distinct character design eliminates confusion. No more 0/O or l/1/I mix-ups.
              </p>
            </div>

            <div class="bg-gray-900 border border-gray-800 rounded-xl p-8 hover:border-gray-700 transition-all">
              <div class="text-4xl mb-4">⚡</div>
              <h3 class="text-xl font-medium mb-3">Performance First</h3>
              <p class="text-gray-400">
                Optimized for fast rendering in terminals and editors. Beautiful without the lag.
              </p>
            </div>

            <div class="bg-gray-900 border border-gray-800 rounded-xl p-8 hover:border-gray-700 transition-all">
              <div class="text-4xl mb-4">🔓</div>
              <h3 class="text-xl font-medium mb-3">Open Source</h3>
              <p class="text-gray-400">
                MIT licensed and hackable. Contribute your own ligatures and improvements.
              </p>
            </div>
          </div>
        </div>
      </section>
      
    <!-- Download CTA -->
      <section class="px-6 py-24 sm:px-12 lg:px-16 bg-gradient-to-br from-gray-900 via-gray-950 to-gray-900">
        <div class="max-w-4xl mx-auto text-center">
          <h2 class="text-4xl md:text-5xl font-light mb-8">
            Ready to Code with <span class="text-blue-400">Intelligence</span>?
          </h2>

          <p class="text-xl text-gray-400 mb-12">
            LANG Mono transforms your code into a visual language that speaks to both humans and parsers.
          </p>

          <div class="flex flex-col sm:flex-row gap-4 justify-center">
            <button
              class="px-8 py-4 bg-gradient-to-r from-blue-600 to-purple-600 text-white font-medium rounded-lg hover:from-blue-700 hover:to-purple-700 transition-all transform hover:-translate-y-0.5 shadow-lg"
              phx-click="join_waitlist"
            >
              Join the Waitlist
            </button>

            <a
              href="https://github.com/yourusername/lang-mono"
              class="px-8 py-4 bg-gray-800 text-white font-medium rounded-lg hover:bg-gray-700 transition-all transform hover:-translate-y-0.5 flex items-center justify-center gap-2"
            >
              <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
                <path
                  fill-rule="evenodd"
                  d="M10 0C4.477 0 0 4.484 0 10.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0110 4.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.203 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.942.359.31.678.921.678 1.856 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0020 10.017C20 4.484 15.522 0 10 0z"
                  clip-rule="evenodd"
                />
              </svg>
              Star on GitHub
            </a>
          </div>

          <p class="text-sm text-gray-500 mt-8">
            * Currently in development. This is a concept demonstration.
          </p>
        </div>
      </section>
      
    <!-- Ligature Detail Modal -->
      <%= if @show_ligature_details && @selected_ligature do %>
        <div
          class="fixed inset-0 bg-black/80 flex items-center justify-center z-50 p-4"
          phx-click="close_ligature"
        >
          <div
            class="bg-gray-900 border border-gray-700 rounded-xl p-8 max-w-md w-full"
            phx-click-away="close_ligature"
          >
            <div class="text-center">
              <div class="text-6xl font-mono mb-4 text-blue-400">{@selected_ligature.to}</div>
              <div class="text-2xl font-mono text-gray-500 mb-6">{@selected_ligature.from}</div>
              <p class="text-gray-400 leading-relaxed">{@selected_ligature.description}</p>
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>

    <style>
      @keyframes gradient {
        0% { background-position: 0% 50%; }
        50% { background-position: 100% 50%; }
        100% { background-position: 0% 50%; }
      }

      .animate-gradient {
        background-size: 200% 200%;
        animation: gradient 3s ease infinite;
      }
    </style>
    """
  end

  @impl true
  def handle_event("update_text", %{"text" => text}, socket) do
    {:noreply, assign(socket, :input_text, text)}
  end

  def handle_event("show_ligature", %{"from" => from, "to" => to, "description" => desc}, socket) do
    {:noreply,
     socket
     |> assign(:show_ligature_details, true)
     |> assign(:selected_ligature, %{from: from, to: to, description: desc})}
  end

  def handle_event("close_ligature", _, socket) do
    {:noreply,
     socket
     |> assign(:show_ligature_details, false)
     |> assign(:selected_ligature, nil)}
  end

  def handle_event("join_waitlist", _, socket) do
    {:noreply,
     put_flash(
       socket,
       :info,
       "Thanks for your interest! We'll notify you when LANG Mono is ready."
     )}
  end

  defp ligatures do
    [
      {"<~>", "⟨~⟩", "LANG", "The LANG operator - semantic parsing boundary"},
      {"->", "→", "Arrow", "Function application and data flow"},
      {"~>", "⟿", "Wave", "Async transformation and wave pipelining"},
      {"=>", "⇒", "Fat Arrow", "Pattern matching and logical implication"},
      {"|>", "▷", "Pipe", "Pipeline operator for data transformation"},
      {"!=", "≠", "Not Equal", "Mathematical inequality"},
      {"~=", "≈", "Approx", "Approximate equality"},
      {"::", "∷", "Type", "Type annotation and specification"},
      {"[[", "⟦", "Left Semantic", "Semantic block start"},
      {"]]", "⟧", "Right Semantic", "Semantic block end"},
      {"<|", "◁", "Back Pipe", "Reverse pipeline operator"},
      {"...", "…", "Ellipsis", "Continuation and ranges"},
      {"<-", "←", "Back Arrow", "Generator and right-to-left flow"},
      {"++", "⧺", "Concat", "List concatenation"},
      {"||", "∥", "Parallel", "Parallel composition"},
      {"&&", "∧", "And", "Logical conjunction"}
    ]
  end

  defp render_with_ligatures(text) do
    ligatures()
    |> Enum.reduce(text, fn {from, to, _, _}, acc ->
      String.replace(acc, from, to)
    end)
    |> Phoenix.HTML.raw()
  end
end
