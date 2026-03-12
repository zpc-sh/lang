# Analysis Pipeline

This document describes the end-to-end flow for filesystem analysis in LANG.

## Overview

- Scan: Use native Rust NIFs to scan a project directory fast.
- Ingest: Create `Lang.Analyses.File` rows (no content persisted) for the run.
- Analyze: Enqueue per-file analysis jobs to compute semantics and style.
- Finalize: Aggregate file stats and complete the run.

## Running the Pipeline Locally

Example: scan a directory, ingest, analyze, and finalize

```elixir
# Create a project and run (session)
{:ok, project} = Lang.Analysis.create_project(%{name: "Local Test", user_id: user.id})
{:ok, run} = Lang.Analyses.Run.create(%{project_id: project.id, metadata: %{}})

# Queue a filesystem scan (ingests files and enqueues per-file analysis)
Lang.Workers.FileSystemScanWorker.scan_async("/path/to/repo", run.id, project.id, user.id,
  analysis_types: ["content_search", "semantic_analysis"]
)

# Optionally, schedule finalize sooner (finalize worker also schedules itself)
Lang.Workers.RunFinalizeWorker.new(%{"run_id" => run.id}) |> Oban.insert()
```


## Components

- `Lang.Native.FSScanner`
  - High-performance filesystem operations (scan, search, preview, code search).
  - Always prefer NIFs over pure Elixir File operations.

- `Lang.Parsers.Filesystem`
  - Synchronous `parse/2` for small scans.
  - Asynchronous path calls `Lang.Workers.FileSystemScanWorker.scan_async/5`.

- `Lang.Workers.FileSystemScanWorker`
  - Performs the scan via `FSScanner.scan/2`.
  - Calls `Lang.Analysis.create_scan_result/1` with the returned tree.
  - Enqueues one `Lang.Workers.FileAnalyzeWorker` job per created file.
  - Broadcasts progress to `analysis:<session_id>` via `Phoenix.PubSub`.
  - Schedules `Lang.Workers.RunFinalizeWorker` (with a small delay) to complete the run.

- `Lang.Workers.FileAnalyzeWorker`
  - Fetches file content (from VFS or job args) and produces:
    - Parser output
    - Text intelligence metrics
    - Stylometrics
  - Calls `Lang.Analysis.complete_analyzed_file/3` on success, or `fail/2` on error.

- `Lang.Workers.RunFinalizeWorker`
  - Reads all files for the run.
  - If any files are not in a terminal state (`:completed|:failed|:skipped`), reschedules itself for a later check.
  - Once all files are terminal, aggregates stats and calls `Run.complete/2`.

## Queues & Workers Matrix

- Queue `:analysis`
  - `Lang.Workers.FileSystemScanWorker`: Scans filesystem and ingests files; schedules finalize; emits scan progress.
  - `Lang.Workers.FileAnalyzeWorker`: Per-file analysis (parser, text intelligence, stylometrics); updates file status.
  - `Lang.Workers.RunFinalizeWorker`: Aggregates counts and completes run; reschedules until all files terminal.
  - `Lang.Workers.SemanticAnalysisWorker`: Advanced semantic analysis; updates `analysis_result` fields.
  - `Lang.Workers.SecurityScanWorker`: Security scanning; updates `analysis_result` fields.
  - `Lang.Workers.DependencyAnalysisWorker`: Dependency analysis; updates `analysis_result` fields.

- Other queues (for reference)
  - `:lsp`: LSP environments (e.g., Filesystem/Cloud environment workers).
  - `:metrics`: Performance/telemetry jobs.
  - `:cleanup`: Cleanup/maintenance jobs.
  - `:billing`: Billing/usage reporting jobs.

## PubSub Topics

- `analysis:<session_id>`
  - `{:scan_progress, status, data}`: Emitted at start/complete.
  - `{:scan_error, data}`: Emitted on failures.

## Ash and Data Flow

- Use `Lang.Analysis` wrapper functions for creating/updating resources.
- `create_scan_result/1` accepts either `files: [...]` or a `tree: %FileNode{}`.
- File content is not persisted; instead we store `content_hash` and `vfs_uri` when available.

## Queues

- `:analysis`: scanning, per-file analysis, finalization, semantic/security/dependency jobs.
- `:lsp`, `:metrics`, `:cleanup`, `:billing`: other subsystems queue usage.

## Error Handling

- Always handle NIF timeouts (`{:error, :timeout}`) and broadcast scan errors.
- Workers use retry/backoff and avoid blocking attempts indefinitely.
