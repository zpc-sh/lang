# Dev Pipeline Checklist

This guide helps you run the analysis pipeline locally end-to-end and inspect it via Oban UI.

## Prereqs

- DB, Oban, and PubSub are running (via `mix phx.server` or your supervision tree).
- Optional: Oban Web mounted at `/oban` in the dev router for a quick dashboard view.

## Steps

1) Create a project and run

```elixir
{:ok, user} = Lang.Accounts.User.create(%{email: "dev@test.local", name: "Dev User", organization_name: "Dev Org"})
{:ok, project} = Lang.Analysis.create_project(%{name: "Local Project", user_id: user.id})
{:ok, run} = Lang.Analyses.Run.create(%{project_id: project.id, metadata: %{}})
```

2) Queue a filesystem scan (ingests and enqueues per-file analysis)

```elixir
Lang.Workers.FileSystemScanWorker.scan_async("/path/to/repo", run.id, project.id, user.id,
  analysis_types: ["content_search", "semantic_analysis"],
  max_depth: 8
)
```

3) (Optional) Nudge finalize sooner

```elixir
Lang.Workers.RunFinalizeWorker.new(%{"run_id" => run.id}) |> Oban.insert()
```

4) Monitor

- In IEx: `Oban.Job |> Lang.Repo.all()`
- In UI: open `/oban` (if Oban Web mounted; gated in dev only)
- PubSub: subscribe to `analysis:#{run.id}` for scan events

5) Review results

```elixir
{:ok, files} =
  Lang.Analyses.File
  |> Ash.Query.filter(analysis_session_id == ^run.id)
  |> Ash.read()

{:ok, completed_run} = Lang.Analyses.Run.by_id(run.id)
completed_run.status
completed_run.file_count
```

## Tuning

Use ENV to tweak finalize timings without code changes:

- `ANALYSIS_FINALIZE_DELAY_SECONDS`
- `ANALYSIS_RUN_FINALIZE_RESCHEDULE_SECONDS`
