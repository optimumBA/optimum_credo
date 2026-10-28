defmodule OptimumCredo.Check.Warning.SleepOutsideTest do
  @moduledoc """
  Finds `Process.sleep/1` and `:timer.sleep/1` calls in production code.

  Sleeping blocks the calling process and usually masks a missing message, retry policy
  or supervision strategy. Calls with `:infinity` are ignored, because they park a
  process on purpose.

  Files under the `ignore_paths` (default `test/` and `priv/`) and `*_test.exs` files are
  skipped. Only the fully qualified call forms (`Process.sleep/1`, `Elixir.Process.sleep/1`,
  `:timer.sleep/1`) are matched; an imported `sleep/1` or an aliased `Process` is not. The path
  patterns are matched against the file name as Credo reports it, so a project checked out under
  a directory called `test/` is skipped when Credo is given absolute paths.

  ## Parameters

  - `ignore_paths`: directory (`"test/"`) or file-suffix patterns to skip.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [ignore_paths: ["test/", "priv/", "_test.exs"]],
    explanations: [
      check: """
      Avoid `Process.sleep/1` and `:timer.sleep/1` outside tests. Prefer messages, timers
      (`Process.send_after/3`), or an explicit retry/backoff library. `sleep(:infinity)` is
      allowed. Opt-in, low priority.
      """,
      params: [ignore_paths: "Directory (ending in `/`) or file-suffix patterns to skip."]
    ]

  alias OptimumCredo.OptimumIdiomsSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    ignore_paths = Params.get(params, :ignore_paths, __MODULE__)

    if OptimumIdiomsSupport.heex_file?(source_file) or
         OptimumIdiomsSupport.path_matches?(source_file.filename, ignore_paths) do
      []
    else
      source_file
      |> Credo.SourceFile.ast()
      |> OptimumIdiomsSupport.unpipe()
      |> Macro.prewalk([], &collect_sleeps(&1, &2, issue_meta))
      |> elem(1)
      |> Enum.reverse()
    end
  end

  defp collect_sleeps({{:., _meta, [module, :sleep]}, meta, [duration]} = node, acc, issue_meta) do
    if sleep_module?(module) and duration != :infinity,
      do: {node, [issue(issue_meta, meta) | acc]},
      else: {node, acc}
  end

  defp collect_sleeps(node, acc, _issue_meta), do: {node, acc}

  defp sleep_module?({:__aliases__, _meta, [:Process]}), do: true
  defp sleep_module?({:__aliases__, _meta, [:"Elixir", :Process]}), do: true
  defp sleep_module?(:timer), do: true
  defp sleep_module?(_module), do: false

  defp issue(issue_meta, meta) do
    format_issue(issue_meta,
      message: "Avoid sleeping outside tests; use messages, timers or explicit retry logic.",
      line_no: meta[:line] || 1
    )
  end
end
