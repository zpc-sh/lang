# Router Domain Registry Layout (Conceptual)

This document outlines the conceptual structure and layout of the domain registry for the `Lang.Router`. It defines how domains are organized, declared, and discovered by the router to enable single-pass, forward-only routing.

## 1. Overview

The `Lang.Router` operates on a registry of domain handlers. This registry is the core mechanism by which the router determines which domain is best suited to handle a given input query. The registry is populated at compile time, ensuring fast lookup and routing decisions.

The goal is to have a registry of approximately **150 domain mini-pipes**, each specializing in a distinct area of functionality (e.g., Documentation queries, Filesystem operations, Session management, Billing inquiries, Data parsing, etc.).

## 2. Registry Structure

The registry itself is a data structure (e.g., a list or map) that holds metadata about each registered domain. This metadata is derived from the domain handler modules themselves.

### 2.1. Registration Mechanism

Domains will register themselves with the router, likely using a macro or a behaviour implementation that is discovered at compile time. This avoids manual registration in a central file, which would become unwieldy.

**Conceptual Elixir Example (using a macro):**

```elixir
# In lib/lang/router.ex
defmodule Lang.Router do
  # Macro to be used by domain handlers
  defmacro register_domain(handler_module) do
    # This macro, at compile time, would:
    # 1. Ensure handler_module implements the Lang.Router.DomainHandler behaviour.
    # 2. Extract metadata (name, cost_class, etc.).
    # 3. Add this metadata to the central registry.
    quote do
      # Implementation details for compile-time registration
    end
  end
end

# In a specific domain handler, e.g., lib/lang/domains/docs.ex
defmodule Lang.Domains.Docs do
  use Lang.Router.DomainHandler
  # This `use` macro would implicitly call `Lang.Router.register_domain(__MODULE__)`

  @impl true
  def can_handle?(input) do
    # Logic to determine if this domain can handle the input
    # e.g., check for keywords like "doc", "help", "API"
    String.contains?(input, ["doc", "help", "API"])
  end

  # ... other callbacks (prepare/1, answer/1, cost_class/0, etc.) ...
end
```

### 2.2. Registry Entry (Metadata)

Each entry in the registry would contain the following information, derived from the domain handler module:

*   **`module`**: The Elixir module name of the domain handler (e.g., `Lang.Domains.Docs`).
*   **`name`**: A unique atom identifier for the domain (e.g., `:docs`, `:fs_ops`). This could default to the module's base name or be explicitly set.
*   **`cost_class`**: (Derived from `handler_module.cost_class/0`) The computational cost (`:low`, `:medium`, `:high`).
*   **`max_ms`**: (Derived from `handler_module.max_ms/0`) The execution time budget.
*   **`max_tokens`**: (Derived from `handler_module.max_tokens/0`) The token budget (for LLM domains).
*   **`handoff_hints`**: (Derived from `handler_module.handoff_hints/1`, if implemented) A list of other domain names this domain might suggest as a next step.

## 3. Domain Categories (Examples for ~150 Domains)

To illustrate the scale and variety, here is a non-exhaustive list of potential domain categories and examples. The actual list will be much longer and more granular.

1.  **Documentation & Help (`:docs`, `:help`, `:tutorials`, `:api_guide`)**
    *   **Purpose:** Answer questions about the system's own documentation, features, and usage.
    *   **Handlers:** `Lang.Domains.Docs`, `Lang.Domains.Help`, `Lang.Domains.Tutorials`.

2.  **Filesystem Operations (`:fs_read`, `:fs_write`, `:fs_list`, `:fs_parse`)**
    *   **Purpose:** Handle commands and queries related to interacting with the filesystem.
    *   **Handlers:** `Lang.Domains.Fs.Read`, `Lang.Domains.Fs.Write`, `Lang.Domains.Fs.List`, `Lang.Domains.Fs.ParseLog`.

3.  **Session Management (`:session_connect`, `:session_status`, `:session_terminate`)**
    *   **Purpose:** Manage user sessions, connects, and status.
    *   **Handlers:** `Lang.Domains.Session.Connect` (might overlap with Control Plane logic but could handle queries *about* sessions), `Lang.Domains.Session.Status`.

4.  **Billing & Account (`:billing_usage`, `:billing_invoice`, `:account_settings`)**
    *   **Purpose:** Provide information and perform actions related to billing and user accounts.
    *   **Handlers:** `Lang.Domains.Billing.Usage`, `Lang.Domains.Billing.Invoice`.

5.  **Data Parsing & Transformation (`:parse_json`, `:parse_csv`, `:transform_data`)**
    *   **Purpose:** Understand and manipulate structured data.
    *   **Handlers:** `Lang.Domains.Parsing.Json`, `Lang.Domains.Parsing.Csv`, `Lang.Domains.Transform.Data`.

6.  **Code Interaction (`:code_run`, `:code_explain`, `:code_lint`)**
    *   **Purpose:** Execute, explain, or analyze code snippets.
    *   **Handlers:** `Lang.Domains.Code.Run` (sandboxed), `Lang.Domains.Code.Explain`.

7.  **External API Calls (`:call_weather_api`, `:call_news_api`)**
    *   **Purpose:** Integrate with external services.
    *   **Handlers:** `Lang.Domains.External.Weather`, `Lang.Domains.External.News`.

8.  **Native System Tools (`:run_ls`, `:run_ps`, `:run_grep`)**
    *   **Purpose:** Provide a controlled interface to common system commands.
    *   **Handlers:** `Lang.Domains.Native.Ls`, `Lang.Domains.Native.Ps`.

9.  **LLM Triage & Escalation (`:llm_triage`, `:llm_committee`, `:llm_judge`)**
    *   **Purpose:** Serve as intermediate or final layers for LLM-based reasoning when deterministic domains cannot suffice.
    *   **Handlers:** `Lang.Domains.LLM.Triage` (cheap model), `Lang.Domains.LLM.Committee` (ensemble), `Lang.Domains.LLM.Judge` (final arbiter).

## 4. Scoring and Selection Process (Conceptual)

When `Lang.Router.route/3` is called:

1.  **L0 Auth/Idempotency:** (Handled upstream) Ensures the request is valid.
2.  **L1 Cache Lookup:** Checks exact-key and semantic caches. If hit, return cached result.
3.  **L2 Deterministic Routing:**
    *   The router iterates through the registry.
    *   For each `domain_handler` in the registry:
        *   `can_handle?(input)` is called.
        *   If it returns `true` or `{:score, float}`, the domain and its score are added to a candidate list.
    *   The candidate list is sorted by score (or `true` is treated as a very high score).
    *   The highest-scoring domain is selected.
    *   The `prepare/1` callback of the selected domain is called.
    *   The `answer/1` callback is called.
        *   If `{:ok, result}`, return the result.
        *   If `{:continue, reason}`, proceed to the next layer.
        *   If `{:error, reason}`, return the error.
4.  **L3 Small Model Triage (Optional):** If L2 results in `{:continue, ...}`, a cheap LLM model (`:llm_triage`) might be invoked to see if it can provide an answer or better route.
5.  **L4 LLM Basecase:** If all else fails and escalation is allowed, the full LLM pipeline (`:llm_committee` or `:llm_judge`) is invoked as a basecase.

This layout ensures the registry is dynamic, discoverable, and manageable even at the scale of ~150 specialized domains, forming the backbone of the deterministic routing engine.