defmodule OptimumCredo.Check.Refactor.WithElseManyClauses do
  @moduledoc """
  Finds `with` expressions whose `else` block has many clauses.

  When every failure maps to the same response the `else` can usually be dropped, with the
  inner functions returning the exact error. A long `else` often means the failures are
  being translated in one place instead of at their source.

  ## Parameters

  - `min_else_clauses`: smallest `else` size to report (default `3`).
  """

  use Credo.Check,
    base_priority: :low,
    category: :refactor,
    param_defaults: [min_else_clauses: 3],
    explanations: [
      check: """
      A `with` with a long `else` usually means inner calls return ambiguous errors. Return
      exact `{:error, reason}` values from the inner functions so the `else` shrinks or
      disappears. Opt-in, low priority; counts clauses only.
      """,
      params: [min_else_clauses: "Smallest `else` clause count that is reported."]
    ]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    min_clauses = Params.get(params, :min_else_clauses, __MODULE__)

    source_file
    |> Credo.Code.prewalk(&check_with(&1, &2, min_clauses, issue_meta))
    |> Enum.reverse()
  end

  defp check_with({:with, meta, args} = node, acc, min_clauses, issue_meta) when is_list(args) do
    count =
      args
      |> List.last()
      |> else_clauses()

    if count >= min_clauses,
      do: {node, [issue(issue_meta, meta, count) | acc]},
      else: {node, acc}
  end

  defp check_with(node, acc, _min_clauses, _issue_meta), do: {node, acc}

  defp else_clauses(options) when is_list(options) do
    case Keyword.get(options, :else) do
      clauses when is_list(clauses) -> length(clauses)
      _other -> 0
    end
  end

  defp else_clauses(_options), do: 0

  defp issue(issue_meta, meta, count) do
    format_issue(issue_meta,
      message:
        "`with` has #{count} `else` clauses; have inner calls return exact errors instead.",
      line_no: meta[:line] || 1
    )
  end
end
