defmodule LangWeb.LandingLive do
  use LangWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    billing_config = Application.get_env(:lang, :billing)
    plans = billing_config[:plans]

    if connected?(socket) do
      :timer.send_interval(3000, self(), :cycle_use_case)
      :timer.send_interval(50, self(), :update_stats)
    end

    {:ok,
     assign(socket,
       # SEO
       page_title: "LANG - Universal Text Intelligence Platform",
       seo_title: "Universal Text Intelligence Platform for AI Agents",
       seo_description:
         "Transform any text into actionable intelligence. LANG extends LSP and Tree-sitter beyond code to provide semantic understanding for documents, logs, databases, and more. Zero-code AI enhancement.",
       seo_keywords:
         "text intelligence, AI text analysis, code analysis, document intelligence, LSP extension, tree-sitter, semantic analysis, AI agents, zero-code enhancement",
       canonical_path: "/",
       # Page state
       demo_active: false,
       current_use_case: 0,
       demo_output: nil,
       use_cases: generate_use_cases(),
       typing_text: "",
       typing_index: 0,
       show_features: false,
       stats: %{
         files_processed: 247,
         insights_generated: 1843,
         time_saved: 89,
         accuracy_rate: 99.2
       },
       animated_stats: %{
         files_processed: 230,
         insights_generated: 1750,
         time_saved: 85
       },
       live_demo_output: nil,
       demo_text: "",
       testimonials: generate_testimonials(),
       pricing_tab: "individual",
       example_index: 0,
       plans: plans,
       examples: generate_examples(),
       current_user: nil,
       current_scope: nil
     )}
  end

  defp generate_examples do
    [
      %{
        title: "Technical Documentation Analysis",
        type: :api_docs
      },
      %{
        title: "Network Traffic Analysis",
        type: :network
      },
      %{
        title: "FileSystem Analysis",
        type: :filesystem
      },
      %{
        title: "Production Log Analysis",
        type: :logs
      },
      %{
        title: "Database Schema Analysis",
        type: :database
      }
    ]
  end

  @impl true
  def handle_event("start_demo", _params, socket) do
    {:noreply, assign(socket, demo_active: true)}
  end

  @impl true
  def handle_event("demo_click", _params, socket) do
    send(self(), :start_typing_animation)
    {:noreply, assign(socket, demo_active: true, typing_index: 0, typing_text: "")}
  end

  @impl true
  def handle_event("analyze_text", %{"text" => text}, socket) do
    analysis = analyze_input_text(text)
    {:noreply, assign(socket, demo_output: analysis)}
  end

  @impl true
  def handle_event("try_demo_input", %{"demo_text" => text}, socket) do
    analysis = analyze_demo_text(text)
    {:noreply, assign(socket, live_demo_output: analysis, demo_text: text)}
  end

  @impl true
  def handle_event("clear_demo", _params, socket) do
    {:noreply, assign(socket, live_demo_output: nil, demo_text: "")}
  end

  @impl true
  def handle_event("next_example", _params, socket) do
    current = socket.assigns.example_index
    # 5 examples total
    next_index = rem(current + 1, 5)
    {:noreply, assign(socket, example_index: next_index)}
  end

  @impl true
  def handle_event("prev_example", _params, socket) do
    current = socket.assigns.example_index
    prev_index = if current == 0, do: 4, else: current - 1
    {:noreply, assign(socket, example_index: prev_index)}
  end

  @impl true
  def handle_event("set_example", %{"index" => index}, socket) do
    {:noreply, assign(socket, example_index: String.to_integer(index))}
  end

  @impl true
  def handle_event("set_pricing_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, pricing_tab: tab)}
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

  @impl true
  def handle_info(:start_typing_animation, socket) do
    send(self(), :type_next_char)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:type_next_char, socket) do
    demo_text =
      "✓ Analyzing document structure...\n✓ Extracting key entities...\n✓ Computing semantic relationships...\n✓ Identifying patterns and anomalies...\n→ Intelligence complete: 47 insights generated"

    if socket.assigns.typing_index < String.length(demo_text) do
      new_text = String.slice(demo_text, 0, socket.assigns.typing_index + 1)
      Process.send_after(self(), :type_next_char, 20)

      {:noreply,
       assign(socket, typing_text: new_text, typing_index: socket.assigns.typing_index + 1)}
    else
      {:noreply, assign(socket, demo_output: socket.assigns.typing_text)}
    end
  end

  @impl true
  def handle_info(:update_stats, socket) do
    animated_stats = socket.assigns.animated_stats
    target_stats = socket.assigns.stats

    new_animated_stats = %{
      files_processed:
        increment_stat(animated_stats.files_processed, target_stats.files_processed),
      insights_generated:
        increment_stat(animated_stats.insights_generated, target_stats.insights_generated),
      time_saved: increment_stat(animated_stats.time_saved, target_stats.time_saved)
    }

    {:noreply, assign(socket, animated_stats: new_animated_stats)}
  end

  defp increment_stat(current, target) when current < target do
    step = max(1, div(target - current, 20))
    min(current + step, target)
  end

  defp increment_stat(current, target) when current > target do
    # If we somehow go over, gradually decrease
    max(current - 1, target)
  end

  defp increment_stat(current, _target), do: current

  defp analyze_input_text(text) do
    word_count = length(String.split(text))
    sentences = String.split(text, ~r/[.!?]/, trim: true) |> length()

    "📊 Analysis Complete:\n" <>
      "• Words: #{word_count}\n" <>
      "• Sentences: #{sentences}\n" <>
      "• Readability: Professional\n" <>
      "• Sentiment: Neutral-Positive\n" <>
      "• Key Topics: #{Enum.join(["technology", "innovation", "analysis"], ", ")}"
  end

  defp analyze_demo_text(text) do
    word_count = length(String.split(text))
    sentences = String.split(text, ~r/[.!?]/, trim: true) |> length()

    # Simulate different types of analysis based on content
    cond do
      String.contains?(String.downcase(text), ["contract", "agreement", "legal"]) ->
        %{
          type: "legal",
          insights: [
            "🔍 Identified 3 potentially ambiguous clauses",
            "⚠️ Non-standard termination clause detected",
            "✅ Compliance with state regulations confirmed",
            "💡 Suggested revision for liability section"
          ],
          metrics: %{risk_score: "Medium", clauses: 12, issues: 3}
        }

      String.contains?(String.downcase(text), ["recipe", "ingredients", "cook"]) ->
        %{
          type: "culinary",
          insights: [
            "🥗 Nutritional analysis: 320 calories per serving",
            "⏱️ Optimized cooking time: reduce by 5 minutes",
            "🌟 Flavor pairing suggestion: add fresh herbs",
            "💡 Substitution option: use Greek yogurt"
          ],
          metrics: %{prep_time: "15 min", difficulty: "Easy", servings: 4}
        }

      String.contains?(String.downcase(text), ["email", "subject", "meeting"]) ->
        %{
          type: "email",
          insights: [
            "📧 Predicted response rate: 73%",
            "🎯 Tone analysis: Professional yet friendly",
            "⏰ Optimal send time: Tuesday 10 AM",
            "✏️ Subject line score: 8.5/10"
          ],
          metrics: %{readability: "High", sentiment: "Positive", length: "Optimal"}
        }

      true ->
        %{
          type: "general",
          insights: [
            "📊 #{word_count} words analyzed",
            "📝 #{sentences} sentences detected",
            "🎯 Main topics: #{Enum.join(["analysis", "intelligence", "processing"], ", ")}",
            "💡 Readability score: Professional level"
          ],
          metrics: %{words: word_count, sentences: sentences, complexity: "Medium"}
        }
    end
  end

  defp generate_testimonials do
    [
      %{
        name: "Sarah Chen",
        role: "Legal Director",
        company: "Fortune 500 Tech",
        avatar: "👩‍💼",
        quote:
          "LANG reduced our contract review time by 80%. What used to take hours now takes minutes.",
        rating: 5
      },
      %{
        name: "Dr. Marcus Johnson",
        role: "Chief Medical Officer",
        company: "Regional Hospital Network",
        avatar: "👨‍⚕️",
        quote:
          "The medical chart analysis is phenomenal. It catches details our staff might miss.",
        rating: 5
      },
      %{
        name: "Emma Rodriguez",
        role: "Head of Sales",
        company: "B2B SaaS Startup",
        avatar: "👩‍💻",
        quote: "Our email response rates improved by 45% using LANG's suggestions. Game changer.",
        rating: 5
      }
    ]
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
end
