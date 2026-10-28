defmodule OptimumCredo.Check.Readability.RedundantFinalAssignment do
  @moduledoc """
  Finds function bodies whose last two expressions are `var = expr` followed by `var`.

  The last expression of a function is its return value, so the assignment can be removed.
  Only `def`, `defp`, `defmacro` and `defmacrop` bodies with a plain variable on the left of
  the match are inspected; destructuring patterns, anonymous functions and `case` branches
  are not.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [],
    explanations: [
      check: """
      Do not bind a value to a variable only to return that variable on the next line.
      Reported for `def`/`defp`/`defmacro`/`defmacrop` bodies with a plain variable match.
      Opt-in, low priority.

      ## Bad

      ```elixir
      def total(items) do
        total = Enum.sum(items)
        total
      end
      ```

      ## Good

      ```elixir
      def total(items), do: Enum.sum(items)
      ```
      """
    ]

  @definitions [:def, :defp, :defmacro, :defmacrop]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, fn
      {kind, _meta, [_head, body]} = node, acc when kind in @definitions ->
        {node, acc ++ body_issues(body, issue_meta)}

      node, acc ->
        {node, acc}
    end)
  end

  defp body_issues([{:do, {:__block__, _meta, expressions}} | _tail], issue_meta) do
    case Enum.take(expressions, -2) do
      [{:=, meta, [{name, _meta, context}, _expr]}, {name, _tuple_meta, context}]
      when is_atom(name) and is_atom(context) ->
        [
          format_issue(issue_meta,
            message:
              "`#{name}` is assigned and returned immediately; return the expression directly.",
            line_no: meta[:line] || 1
          )
        ]

      _other ->
        []
    end
  end

  defp body_issues(_body, _issue_meta), do: []
end
