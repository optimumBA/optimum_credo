defmodule OptimumCredo.Check.Refactor.ConditionalOnParameter do
  @moduledoc """
  Hints that a function body only branches on one of its own parameters.

  Reported for `def`/`defp` whose entire body is either

  - a `case` on a plain parameter variable with at least `min_case_clauses` clauses, or
  - an `if`/`unless` whose condition compares a plain parameter variable (`==`, `===`,
    `in`, `is_*` guards).

  Such a function can often be several clauses with pattern matching or guards. A `case` whose
  clauses are only `true`/`false` is left to `CaseTrueFalse`. Bodies with more than one
  expression, branches on computed values, and `cond` are not inspected. This is a style hint
  and will sometimes be wrong.

  ## Parameters

  - `min_case_clauses`: smallest `case` size to report (default `2`).
  - `check_if`: also report `if`/`unless` (default `true`).
  """

  use Credo.Check,
    base_priority: :low,
    category: :refactor,
    param_defaults: [min_case_clauses: 2, check_if: true],
    explanations: [
      check: """
      Prefer several function clauses or guards over a single body that is just a `case`
      or `if` on one of the parameters. Opt-in, low priority; only single-expression bodies
      are inspected.

      ## Bad

      ```elixir
      def label(kind) do
        case kind do
          :admin -> "Admin"
          :member -> "Member"
        end
      end
      ```

      ## Good

      ```elixir
      def label(:admin), do: "Admin"
      def label(:member), do: "Member"
      ```
      """,
      params: [
        min_case_clauses: "Minimum number of `case` clauses to report.",
        check_if: "Also report `if`/`unless` that test a parameter."
      ]
    ]

  @definitions [:def, :defp]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    min_clauses = Params.get(params, :min_case_clauses, __MODULE__)
    check_if = Params.get(params, :check_if, __MODULE__)

    source_file
    |> Credo.Code.prewalk(&check_definition(&1, &2, {min_clauses, check_if}, issue_meta))
    |> Enum.reverse()
  end

  defp check_definition(
         {kind, _meta, [head, [do: body]]} = node,
         acc,
         {min_clauses, check_if},
         issue_meta
       )
       when kind in @definitions do
    case branch(body, parameters(head), min_clauses, check_if) do
      nil -> {node, acc}
      {meta, what} -> {node, [issue(issue_meta, meta, what) | acc]}
    end
  end

  defp check_definition(node, acc, _options, _issue_meta), do: {node, acc}

  defp parameters({:when, _meta, [head | _tail]}), do: parameters(head)

  defp parameters({_name, _meta, args}) when is_list(args) do
    for {name, _meta, context} <- args,
        is_atom(name) and is_atom(context) and not underscored?(name),
        do: name
  end

  defp parameters(_head), do: []

  defp underscored?(name) do
    name
    |> Atom.to_string()
    |> String.starts_with?("_")
  end

  defp branch(
         {:case, meta, [{name, _meta, context}, [do: clauses]]},
         parameters,
         min_clauses,
         _check_if
       )
       when is_atom(name) and is_atom(context) and is_list(clauses) do
    if name in parameters and length(clauses) >= min_clauses and not boolean_clauses?(clauses),
      do: {meta, "a `case` on `#{name}`"}
  end

  defp branch({kind, meta, [condition | _tail]}, parameters, _min_clauses, true)
       when kind in [:if, :unless] do
    if tests_parameter?(condition, parameters),
      do: {meta, "#{article(kind)} `#{kind}` on a parameter"}
  end

  defp branch(_body, _parameters, _min_clauses, _check_if), do: nil

  defp boolean_clauses?(clauses),
    do: Enum.all?(clauses, &match?({:->, _, [[boolean], _]} when is_boolean(boolean), &1))

  defp tests_parameter?({op, _meta, [left, right]}, parameters) when op in [:==, :===, :in],
    do: parameter?(left, parameters) and literal?(right)

  defp tests_parameter?({guard, _meta, [argument]}, parameters) when is_atom(guard) do
    guard
    |> Atom.to_string()
    |> String.starts_with?("is_") and parameter?(argument, parameters)
  end

  defp tests_parameter?(_condition, _parameters), do: false

  defp parameter?({name, _meta, context}, parameters) when is_atom(name) and is_atom(context),
    do: name in parameters

  defp parameter?(_expression, _parameters), do: false

  defp literal?(value) when is_atom(value) or is_binary(value) or is_number(value), do: true
  defp literal?(list) when is_list(list), do: Enum.all?(list, &literal?/1)
  defp literal?(_value), do: false

  defp article(:if), do: "an"
  defp article(:unless), do: "an"

  defp issue(issue_meta, meta, what) do
    format_issue(issue_meta,
      message: "Function body is only #{what}; consider separate clauses or guards.",
      line_no: meta[:line] || 1
    )
  end
end
