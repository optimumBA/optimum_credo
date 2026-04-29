defmodule OptimumCredo.Check.Refactor.CaseTrueFalse do
  @moduledoc """
  A check that finds `case` expressions whose only clauses are literal `true` and
  literal `false`, suggesting they be replaced with an `if` expression.

  A `case` with exactly two clauses matching `true` and `false` (in any order,
  no wildcards, no other patterns) is semantically identical to an `if/else` and
  should use that form for clarity.

  **Strict mode**: this check fires ONLY when the `case` has EXACTLY two clauses
  and both are literal `true`/`false`. A three-clause `case` with `true`, `false`,
  and `_other ->` does NOT fire — the wildcard makes the semantics different and the
  refactor is less mechanical.

  ## Examples

  **Bad:**
  ```elixir
  case Map.get(attrs, :active) do
    true -> activate(user)
    false -> deactivate(user)
  end
  ```

  **Good:**
  ```elixir
  if Map.get(attrs, :active) do
    activate(user)
  else
    deactivate(user)
  end
  ```
  """

  use Credo.Check,
    base_priority: :normal,
    category: :refactor,
    explanations: [
      check: """
      A `case` expression with only `true ->` and `false ->` clauses should be
      replaced with an `if` expression.

      ## Examples

      **Bad:**
      ```elixir
      case condition do
        true -> :yes
        false -> :no
      end
      ```

      **Good:**
      ```elixir
      if condition do
        :yes
      else
        :no
      end
      ```
      """
    ]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse(ast, issues, issue_meta) do
    case find_case_true_false(ast, issue_meta) do
      nil -> {ast, issues}
      issue -> {ast, [issue | issues]}
    end
  end

  defp find_case_true_false({:case, meta, [_subject, [do: clauses]]}, issue_meta)
       when length(clauses) == 2 do
    patterns = Enum.map(clauses, fn {:->, _arrow_meta, [[pattern], _body]} -> pattern end)

    if Enum.sort(patterns) == [false, true] do
      format_issue(issue_meta,
        message: "Replace 'case x do true -> ...; false -> ... end' with an 'if' expression.",
        line_no: meta[:line] || 1
      )
    end
  end

  defp find_case_true_false(_ast, _issue_meta), do: nil
end
