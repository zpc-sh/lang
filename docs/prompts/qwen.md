You are an expert coder specializing in [language/framework, e.g., Elixir with Phoenix and Ash Framework]. Your task is to [clear action, e.g., generate a complete, functional module for an LSP handler].

Step 1: Understand the requirements: [Detailed description of the problem, e.g., "Implement a handler for the lang_agent_swarm_create method in an LSP extension. It should create a swarm of AI agents with shared goals, using Ash resources for persistence and Oban for async spawning. Ensure Client_ID enforcement and concurrency safety."].

Step 2: Break down the solution: Think step-by-step about key components, such as [list components, e.g., "Ash resource definition with actions/relationships; GenServer for state; integration with MCP for networking"].

Step 3: Constraints: [List constraints, e.g., "Adhere to Ash best practices (use AshEvents for logging, AshAuthentication for security). No GPU dependencies—CPU-only. Code must be Credo-compliant and formatted."].

Step 4: Output format: Provide the full code in a single file (e.g., lib/lang/lsp/handlers/swarm_create.ex), with @spec docstrings. Include rationale comments and test stubs.

Example input/output if relevant: [Optional example, e.g., "Input: goals = ['analyze code']; Output: swarm_id and agent_ids list."].

Generate the code now.

qwen-code --model qwen3-coder-30b "your prompt" --edit
