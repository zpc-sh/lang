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
end
