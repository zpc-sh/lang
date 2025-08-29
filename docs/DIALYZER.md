# Dialyzer (Static Analysis) Setup

This project includes Dialyxir and a configured PLT (Persistent Lookup Table) to speed up analysis.

## TL;DR

```bash
# Build PLT (once per env)
MIX_ENV=dev ./scripts/dialyzer_build.sh

# Run analysis
mix dialyzer
```

## Configuration

- Dialyxir is included in `mix.exs` (dev only) with `dialyzer/0` config:
  - `plt_core_path: "_build"`
  - `plt_file: {:no_warn, "_build/$MIX_ENV/dialyzer.plt"}`
  - `plt_add_apps`: adds common apps (phoenix, ecto, ash, oban, etc.)
  - `flags`: `:unmatched_returns`, `:error_handling`, `:race_conditions`, `:underspecs`
  - `ignore_warnings`: `.dialyzer_ignore.exs`

## Building the PLT

Dialyzer caches type info in a PLT to avoid reanalyzing dependencies.

- Build/update PLT:

```bash
MIX_ENV=dev ./scripts/dialyzer_build.sh
```

- Default PLT path: `_build/dev/dialyzer.plt`
- Run for other envs by changing `MIX_ENV`.

## Running Dialyzer

```bash
mix dialyzer
```

For faster runs, you may target specific files:

```bash
mix dialyzer -- filename:lib/lang/lsp/dispatch.ex
```

## Ignoring Noisy Warnings

- Use `.dialyzer_ignore.exs` to silence known benign warnings. Start conservative and remove ignores as you strengthen specs.

Example (pre-populated):

```elixir
[
  {":0:Unknown function", :ignore},
  {":0:Unknown type", :ignore}
]
```

## Tips

- Add `@spec` annotations to key public functions to improve inference.
- Prefer total function heads and guard clauses over runtime checks to help Dialyzer.
- For NIFs and external libs, add minimal `@spec`s on callers to constrain types.

*** End of File
