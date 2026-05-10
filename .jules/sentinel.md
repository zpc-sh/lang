## 2024-05-10 - Unsafe Dynamic Module Dispatch in Agent Testing
**Vulnerability:** Remote Code Execution (RCE) via `apply/3` with untrusted user input in `Lang.Workers.LSPComparisonWorker`. The `agent_variant["provider_module"]` string was directly converted to an atom and invoked.
**Learning:** Elixir's `apply(module, function, args)` allows arbitrary function execution if the module name is controlled by an attacker. When dynamically calling generated agent modules under a specific namespace, we must strictly validate the namespace.
**Prevention:** Always validate that dynamic module strings start with the expected prefix (e.g., `"Elixir.Lang.Testing.Variants."`) before converting to an atom and invoking `apply/3`.
