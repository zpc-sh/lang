defmodule LangWeb.DemoLive do
  use LangWeb, :live_view

  @demo_steps [
    %{
      text: "import { User } from '../database/UserModel';",
      type: :violation,
      title: "🚫 Architecture Violation Detected",
      description:
        "Components should not directly import from the database layer. This violates clean architecture principles.",
      action: "Suggested fix: Use UserService.getUser() instead",
      delay: 3000
    },
    %{
      text: "import { UserService } from '../services/UserService';",
      type: :suggestion,
      title: "✅ Architecture Compliance",
      description:
        "Perfect! Components should import from the service layer. This follows clean architecture patterns.",
      action: "LANG automatically suggests proper patterns",
      delay: 2000
    },
    %{
      text: "const userData = await UserService.getCurrentUser();",
      type: :success,
      title: "🎯 Best Practice Applied",
      description:
        "Excellent use of service layer abstraction. This promotes loose coupling and testability.",
      action: "Code quality score improved by 23%",
      delay: 2500
    },
    %{
      text: "// Direct SQL query in component - AVOID",
      type: :warning,
      title: "⚠️ Potential Code Smell",
      description:
        "Comments suggest direct database access patterns. Consider using repository pattern instead.",
      action: "Refactoring suggestion: Extract to UserRepository",
      delay: 2000
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:demo_started, false)
     |> assign(:demo_step, 0)
     |> assign(:current_text, "")
     |> assign(:intelligence_items, [])
     |> assign(:typing_active, false)
     |> assign(:progress, 0)
     |> assign(:file_violations, %{})
     |> assign(:architecture_violations, false)
     |> assign(:code_quality_score, 72)
     |> assign(:violations_count, 0)
     |> assign(:suggestions_count, 0)}
  end

  @impl true
  def handle_event("start_demo", _params, socket) do
    send(self(), :run_demo_step)

    {:noreply,
     socket
     |> assign(:demo_started, true)
     |> assign(:progress, 0)
     |> assign(:current_text, "")
     |> assign(:intelligence_items, [])}
  end

  @impl true
  def handle_event("restart_demo", _params, socket) do
    {:noreply,
     socket
     |> assign(:demo_started, false)
     |> assign(:demo_step, 0)
     |> assign(:current_text, "")
     |> assign(:intelligence_items, [])
     |> assign(:typing_active, false)
     |> assign(:progress, 0)
     |> assign(:file_violations, %{})
     |> assign(:architecture_violations, false)
     |> assign(:code_quality_score, 72)
     |> assign(:violations_count, 0)
     |> assign(:suggestions_count, 0)}
  end

  # The magic: LiveView handles real-time updates naturally
  @impl true
  def handle_info(:run_demo_step, socket) do
    if socket.assigns.demo_step >= length(@demo_steps) do
      # Demo complete
      new_item = %{
        type: :complete,
        title: "🎉 Demo Complete!",
        description:
          "This is LANG - real-time architecture intelligence for your entire codebase.",
        action: "Ready to transform your development workflow?"
      }

      {:noreply,
       socket
       |> assign(:progress, 100)
       |> assign(:intelligence_items, socket.assigns.intelligence_items ++ [new_item])}
    else
      step = Enum.at(@demo_steps, socket.assigns.demo_step)

      # Start typing animation
      send(self(), {:type_text, step.text, 0})

      {:noreply,
       socket
       |> assign(:typing_active, true)
       |> assign(:progress, (socket.assigns.demo_step + 1) / length(@demo_steps) * 100)}
    end
  end

  # LiveView's natural streaming: type character by character
  @impl true
  def handle_info({:type_text, text, index}, socket) do
    if index >= String.length(text) do
      # Typing complete, show intelligence
      step = Enum.at(@demo_steps, socket.assigns.demo_step)

      # Schedule intelligence item appearance
      Process.send_after(self(), {:show_intelligence, step}, 500)

      {:noreply,
       socket
       |> assign(:typing_active, false)
       |> assign(:current_text, text)}
    else
      # Continue typing
      char = String.at(text, index)
      new_text = socket.assigns.current_text <> char

      # Schedule next character (simulate typing speed)
      Process.send_after(self(), {:type_text, text, index + 1}, 80)

      {:noreply, assign(socket, :current_text, new_text)}
    end
  end

  @impl true
  def handle_info({:show_intelligence, step}, socket) do
    new_item = %{
      type: step.type,
      title: step.title,
      description: step.description,
      action: step.action
    }

    # Update file tree and architecture based on step type
    updated_socket =
      socket
      |> assign(:intelligence_items, socket.assigns.intelligence_items ++ [new_item])
      |> update_file_violations(step.type)
      |> update_architecture_state(step.type)
      |> update_metrics(step.type)

    # Schedule next step
    Process.send_after(self(), :advance_demo, step.delay)

    {:noreply, updated_socket}
  end

  @impl true
  def handle_info(:advance_demo, socket) do
    send(self(), :run_demo_step)
    {:noreply, assign(socket, :demo_step, socket.assigns.demo_step + 1)}
  end

  defp update_file_violations(socket, :violation) do
    assign(socket, :file_violations, Map.put(socket.assigns.file_violations, "user_model", true))
  end

  defp update_file_violations(socket, :suggestion) do
    socket
    |> assign(:file_violations, Map.put(socket.assigns.file_violations, "user_service", true))
    |> assign(:file_violations, Map.delete(socket.assigns.file_violations, "user_model"))
  end

  defp update_file_violations(socket, :success) do
    assign(
      socket,
      :file_violations,
      Map.put(socket.assigns.file_violations, "user_service", :success)
    )
  end

  defp update_file_violations(socket, _), do: socket

  defp update_architecture_state(socket, :violation) do
    assign(socket, :architecture_violations, true)
  end

  defp update_architecture_state(socket, :suggestion) do
    assign(socket, :architecture_violations, false)
  end

  defp update_architecture_state(socket, _), do: socket

  defp update_metrics(socket, :violation) do
    socket
    |> assign(:violations_count, socket.assigns.violations_count + 1)
    |> assign(:code_quality_score, max(socket.assigns.code_quality_score - 8, 0))
  end

  defp update_metrics(socket, :suggestion) do
    socket
    |> assign(:suggestions_count, socket.assigns.suggestions_count + 1)
    |> assign(:code_quality_score, min(socket.assigns.code_quality_score + 15, 100))
  end

  defp update_metrics(socket, :success) do
    assign(socket, :code_quality_score, min(socket.assigns.code_quality_score + 10, 100))
  end

  defp update_metrics(socket, _), do: socket

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={assigns[:current_user]} current_scope={assigns[:current_scope]}>
    <!-- Progress Bar -->
    <div class="fixed top-0 left-0 w-full z-50 bg-base-300 h-1">
      <div
        class="h-full bg-gradient-to-r from-primary to-secondary transition-all duration-500 ease-out"
        style={"width: #{@progress}%"}
      >
      </div>
    </div>

    <!-- Demo Introduction Banner -->
    <div class={[
      "alert shadow-lg mb-0 rounded-none border-0",
      if(@demo_started, do: "hidden", else: "bg-gradient-to-r from-primary/10 to-secondary/10")
    ]}>
      <div class="flex items-center gap-3">
        <div class="text-2xl">🧠</div>
        <div>
          <h3 class="font-bold">Experience LANG's Architecture Intelligence</h3>
          <div class="text-sm opacity-70">
            Watch real-time code analysis and architectural guidance in action
          </div>
        </div>
      </div>
      <div class="flex-none">
        <button class="btn btn-primary btn-sm" phx-click="start_demo">
          <.icon name="hero-play" class="w-4 h-4" /> Start Interactive Demo
        </button>
      </div>
    </div>

    <!-- Main Demo Layout -->
    <div class="grid grid-cols-1 xl:grid-cols-4 min-h-screen bg-base-200">
      
    <!-- Code Editor Panel -->
      <div class="xl:col-span-3 bg-base-100 flex flex-col">
        
    <!-- Editor Header -->
        <div class="navbar bg-base-300 min-h-12 border-b border-base-content/10">
          <div class="navbar-start">
            <span class="text-sm font-mono flex items-center gap-2">
              <.icon name="hero-document-text" class="w-4 h-4" /> UserProfile.tsx
              <%= if @typing_active do %>
                <span class="loading loading-dots loading-xs text-primary"></span>
              <% end %>
            </span>
          </div>
          <div class="navbar-end">
            <div class="stats stats-horizontal text-xs">
              <div class="stat py-2 px-3">
                <div class="stat-title text-xs">Quality Score</div>
                <div class={["stat-value text-sm", quality_score_color(@code_quality_score)]}>
                  {@code_quality_score}%
                </div>
              </div>
            </div>
          </div>
        </div>
        
    <!-- File Explorer -->
        <div class="bg-base-200 p-4 border-b border-base-content/10">
          <div class="text-sm font-mono">
            <div class="flex items-center gap-2 mb-2">
              <.icon name="hero-folder" class="w-4 h-4" />
              <span class="font-semibold">Project Structure</span>
            </div>

            <div class="space-y-1 ml-4">
              <div class="flex items-center gap-2">
                <.icon name="hero-folder-open" class="w-3 h-3" />
                <span>src/</span>
              </div>

              <div class="ml-4 space-y-1">
                <div class="flex items-center gap-2">
                  <.icon name="hero-folder-open" class="w-3 h-3" />
                  <span>components/</span>
                </div>
                <div class="ml-4 flex items-center gap-2">
                  <.icon name="hero-document" class="w-3 h-3" />
                  <span class="text-info">UserProfile.tsx</span>
                  <span class="badge badge-info badge-xs">active</span>
                </div>
                
    <!-- Database folder -->
                <div class="flex items-center gap-2">
                  <.icon name="hero-folder" class="w-3 h-3" />
                  <span class={["transition-colors", violation_class(@file_violations["user_model"])]}>
                    database/
                  </span>
                  <%= if @file_violations["user_model"] do %>
                    <span class="badge badge-error badge-xs animate-pulse">violation</span>
                  <% end %>
                </div>
                <div class="ml-4 flex items-center gap-2">
                  <.icon name="hero-document" class="w-3 h-3" />
                  <span class={["transition-colors", violation_class(@file_violations["user_model"])]}>
                    UserModel.ts
                  </span>
                </div>
                
    <!-- Services folder -->
                <div class="flex items-center gap-2">
                  <.icon name="hero-folder" class="w-3 h-3" />
                  <span class={[
                    "transition-colors",
                    suggestion_class(@file_violations["user_service"])
                  ]}>
                    services/
                  </span>
                  <%= if @file_violations["user_service"] == true do %>
                    <span class="badge badge-success badge-xs">suggested</span>
                  <% end %>
                  <%= if @file_violations["user_service"] == :success do %>
                    <span class="badge badge-accent badge-xs">✨ optimized</span>
                  <% end %>
                </div>
                <div class="ml-4 flex items-center gap-2">
                  <.icon name="hero-document" class="w-3 h-3" />
                  <span class={[
                    "transition-colors",
                    suggestion_class(@file_violations["user_service"])
                  ]}>
                    UserService.ts
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
        
    <!-- Code editor -->
        <div class="flex-1 p-6 bg-neutral text-neutral-content font-mono">
          <div
            class="mockup-code bg-base-300 text-base-content h-full text-sm"
            phx-no-curly-interpolation
          >
            <pre data-prefix="1"><code>import React from 'react';</code></pre>
            <pre data-prefix="2"><code></code></pre>
            <pre data-prefix="3"><code><%= @current_text %><%= if @typing_active, do: "|", else: "" %></code></pre>
            <pre data-prefix="4"><code></code></pre>
            <pre data-prefix="5"><code>export function UserProfile() {</code></pre>
            <pre data-prefix="6"><code>  return React.createElement('div', null, 'Profile');</code></pre>
            <pre data-prefix="7"><code>}</code></pre>
          </div>
        </div>
      </div>
      
    <!-- Intelligence Panel -->
      <div class="bg-base-300 flex flex-col border-l border-base-content/10">
        
    <!-- Panel Header -->
        <div class="navbar bg-base-300 min-h-12 border-b border-base-content/10">
          <div class="navbar-start">
            <span class="text-sm font-semibold flex items-center gap-2">
              <.icon name="hero-cpu-chip" class="w-4 h-4 text-primary" /> LANG Intelligence
            </span>
          </div>
        </div>
        
    <!-- Metrics Dashboard -->
        <div class="p-4 bg-base-200 border-b border-base-content/10">
          <div class="stats stats-vertical w-full text-xs">
            <div class="stat py-2">
              <div class="stat-title text-xs">Violations</div>
              <div class="stat-value text-lg text-error">{@violations_count}</div>
            </div>
            <div class="stat py-2">
              <div class="stat-title text-xs">Suggestions</div>
              <div class="stat-value text-lg text-success">{@suggestions_count}</div>
            </div>
          </div>
        </div>
        
    <!-- Intelligence Feed -->
        <div class="flex-1 p-4 overflow-y-auto space-y-3">
          
    <!-- Initial Demo Step -->
          <%= if not @demo_started do %>
            <div class="card bg-gradient-to-r from-primary/20 to-secondary/20 border-primary/30">
              <div class="card-body p-4">
                <h3 class="card-title text-sm flex items-center gap-2">
                  <.icon name="hero-rocket-launch" class="w-4 h-4" /> Demo Ready
                </h3>
                <p class="text-xs opacity-80">
                  Watch LANG provide real-time architectural guidance as you code
                </p>
              </div>
            </div>
          <% end %>
          
    <!-- Intelligence Items -->
          <%= for {item, index} <- Enum.with_index(@intelligence_items) do %>
            <div
              class={[
                "alert shadow-lg animate-fade-in text-sm",
                intelligence_alert_class(item.type)
              ]}
              style={"animation-delay: #{index * 0.1}s"}
            >
              <div class="w-full">
                <div class="flex items-start gap-2 mb-2">
                  <div class="flex-shrink-0 mt-0.5">
                    {intelligence_icon(item.type)}
                  </div>
                  <div class="flex-1">
                    <h3 class="font-bold text-sm">{item.title}</h3>
                    <p class="text-xs opacity-80 mt-1">{item.description}</p>
                  </div>
                </div>
                <div class="mt-3 p-2 bg-base-100/50 rounded text-xs border-l-2 border-current">
                  {item.action}
                </div>
              </div>
            </div>
          <% end %>
          
    <!-- Demo Complete Actions -->
          <%= if @progress >= 100 do %>
            <div class="card bg-gradient-to-r from-accent/20 to-primary/20 border-accent/30 mt-6">
              <div class="card-body p-4">
                <h2 class="card-title text-sm flex items-center gap-2">
                  <.icon name="hero-check-badge" class="w-4 h-4" /> Ready to get started?
                </h2>
                <p class="text-xs opacity-80 mb-3">
                  Transform your development workflow with AI-powered architecture intelligence
                </p>
                <div class="card-actions justify-between">
                  <button class="btn btn-ghost btn-xs" phx-click="restart_demo">
                    <.icon name="hero-arrow-path" class="w-3 h-3" /> Replay Demo
                  </button>
                  <.link navigate="/auth" class="btn btn-primary btn-xs">
                    <.icon name="hero-sparkles" class="w-3 h-3" /> Start Free Trial
                  </.link>
                </div>
              </div>
            </div>
          <% end %>
        </div>
        
    <!-- Architecture Health -->
        <div class="p-4 bg-base-200 border-t border-base-content/10">
          <h4 class="text-sm font-semibold mb-3 flex items-center gap-2">
            <.icon name="hero-chart-bar" class="w-4 h-4" /> Architecture Health
          </h4>
          <div class="flex flex-wrap gap-2">
            <div class="badge badge-primary badge-outline text-xs">Components</div>
            <div class="badge badge-secondary badge-outline text-xs">Services</div>
            <div class={[
              "badge badge-outline text-xs transition-all",
              if(@architecture_violations, do: "badge-error animate-pulse", else: "badge-neutral")
            ]}>
              Database
            </div>
          </div>
          
    <!-- Health Score -->
          <div class="mt-3">
            <div class="flex justify-between text-xs mb-1">
              <span>Health Score</span>
              <span class={quality_score_color(@code_quality_score)}>{@code_quality_score}%</span>
            </div>
            <progress
              class={["progress w-full h-2", quality_progress_class(@code_quality_score)]}
              value={@code_quality_score}
              max="100"
            >
            </progress>
          </div>
        </div>
      </div>
    </div>

    <style>
      @keyframes fade-in {
        from {
          opacity: 0;
          transform: translateY(10px);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }

      .animate-fade-in {
        animation: fade-in 0.5s ease-out forwards;
      }
    </style>
    </Layouts.app>
    """
  end

  # Helper functions
  defp violation_class(true), do: "text-error"
  defp violation_class(_), do: ""

  defp suggestion_class(true), do: "text-success"
  defp suggestion_class(:success), do: "text-accent"
  defp suggestion_class(_), do: ""

  defp quality_score_color(score) when score >= 80, do: "text-success"
  defp quality_score_color(score) when score >= 60, do: "text-warning"
  defp quality_score_color(_), do: "text-error"

  defp quality_progress_class(score) when score >= 80, do: "progress-success"
  defp quality_progress_class(score) when score >= 60, do: "progress-warning"
  defp quality_progress_class(_), do: "progress-error"

  defp intelligence_alert_class(:violation), do: "alert-error"
  defp intelligence_alert_class(:suggestion), do: "alert-success"
  defp intelligence_alert_class(:success), do: "alert-info"
  defp intelligence_alert_class(:warning), do: "alert-warning"
  defp intelligence_alert_class(:complete), do: "alert-info"
  defp intelligence_alert_class(_), do: "alert-info"

  defp intelligence_icon(:violation) do
    assigns = %{}

    ~H"""
    <.icon name="hero-exclamation-triangle" class="w-4 h-4 text-error" />
    """
  end

  defp intelligence_icon(:suggestion) do
    assigns = %{}

    ~H"""
    <.icon name="hero-check-circle" class="w-4 h-4 text-success" />
    """
  end

  defp intelligence_icon(:success) do
    assigns = %{}

    ~H"""
    <.icon name="hero-sparkles" class="w-4 h-4 text-accent" />
    """
  end

  defp intelligence_icon(:warning) do
    assigns = %{}

    ~H"""
    <.icon name="hero-exclamation-circle" class="w-4 h-4 text-warning" />
    """
  end

  defp intelligence_icon(:complete) do
    assigns = %{}

    ~H"""
    <.icon name="hero-check-badge" class="w-4 h-4 text-primary" />
    """
  end

  defp intelligence_icon(_) do
    assigns = %{}

    ~H"""
    <.icon name="hero-information-circle" class="w-4 h-4" />
    """
  end
end
