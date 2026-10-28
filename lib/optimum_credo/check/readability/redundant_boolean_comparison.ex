defmodule OptimumCredo.Check.Readability.RedundantBooleanComparison do
  @moduledoc """
  Finds comparisons of a boolean-valued expression against `true` or `false`, such as
  `String.valid?(x) == true` or `(a > b) != false`.

  By default only expressions that are provably boolean are reported: comparison operators
  (including `=~` and `in`), `not`/`!`, the `Kernel` guards and predicates (`is_binary/1`,
  `match?/2`, ...), and `?` functions of standard-library modules (`Enum.empty?/1`,
  `String.valid?/1`, ...). A name ending in `?` is only a convention: a project function such
  as `valid?(x)` may return `nil` or another truthy value, and then `valid?(x) == true` is
  stricter than `valid?(x)`, so unknown `?` calls are left alone unless `trust_question_mark`
  is set. A plain variable or arbitrary call is likewise left alone because it may be `nil`.
  The message says whether to use the expression directly or negate it with `not`.

  ## Parameters

  - `trust_question_mark`: when `true`, treat every `?`-suffixed function and every `is_*`
    call as returning a boolean (default `false`).
  - `strict`: when `true`, report every comparison with a boolean literal, including plain
    variables and arbitrary calls (default `false`).
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [strict: false, trust_question_mark: false],
    explanations: [
      check: """
      Comparing a boolean-valued expression with `true` or `false` is redundant: use the
      expression itself, or `not` / `!` for the negation.

      By default only provably boolean operands are reported (comparisons, `not`/`!`, Kernel
      guards and standard-library `?` predicates). Set `trust_question_mark: true` to also
      accept project `?`/`is_*` functions as boolean, or `strict: true` to report variables and
      arbitrary calls, which may be `nil` and therefore not equivalent. Opt-in, low priority.

      ## Bad

      ```elixir
      if Enum.empty?(list) == true, do: :none
      ```

      ## Good

      ```elixir
      if Enum.empty?(list), do: :none
      ```
      """,
      params: [
        trust_question_mark: "Treat project `?`-suffixed and `is_*` functions as boolean.",
        strict: "Report comparisons for every operand, not only certainly-boolean ones."
      ]
    ]

  @comparison_ops [:==, :===, :!=, :!==]
  @boolean_ops [:==, :===, :!=, :!==, :<, :>, :<=, :>=, :=~, :in]
  @guards ~w(is_atom is_binary is_bitstring is_boolean is_exception is_float is_function is_integer
             is_list is_map is_map_key is_nil is_number is_pid is_port is_reference is_struct
             is_tuple is_non_struct_map is_exception match? function_exported? macro_exported?)a
  # Standard-library modules whose `?` functions are documented to return `true | false`.
  @predicate_modules ~w(Enum String Map MapSet Keyword List Process File Code Regex Version
                        Module Macro Date DateTime Time NaiveDateTime Range Integer Float Tuple
                        Atom Path Kernel Calendar Application Stream Bitwise)a

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    strict = Params.get(params, :strict, __MODULE__)
    trust_question_mark = Params.get(params, :trust_question_mark, __MODULE__)

    source_file
    |> Credo.Code.prewalk(fn
      {op, meta, [left, right]} = node, acc when op in @comparison_ops ->
        case operand(left, right, strict, trust_question_mark) do
          nil -> {node, acc}
          literal -> {node, [issue(issue_meta, meta, op, literal) | acc]}
        end

      node, acc ->
        {node, acc}
    end)
    |> Enum.reverse()
  end

  defp operand(left, right, strict, trust) when is_boolean(right),
    do: operand(left, right, strict, trust, right)

  defp operand(left, right, strict, trust) when is_boolean(left),
    do: operand(right, left, strict, trust, left)

  defp operand(_left, _right, _strict, _trust), do: nil

  defp operand(expression, literal, strict, trust, literal) do
    if not is_boolean(expression) and (strict or boolean_expression?(expression, trust)),
      do: literal
  end

  defp boolean_expression?({:|>, _meta, [_first, call]}, trust),
    do: boolean_expression?(call, trust)

  defp boolean_expression?({op, _meta, [_first, _second]}, _trust) when op in @boolean_ops,
    do: true

  defp boolean_expression?({op, _meta, [_item]}, _trust) when op in [:not, :!], do: true

  defp boolean_expression?(
         {{:., _meta, [{:__aliases__, _alias_meta, path}, name]}, _tuple_meta, args},
         trust
       )
       when is_list(args) and is_atom(name) do
    cond do
      path in [[:Kernel]] and name in @guards -> true
      List.last(path) in @predicate_modules and question?(name) -> true
      true -> trust and question?(name)
    end
  end

  defp boolean_expression?({{:., _meta, [_receiver, name]}, _tuple_meta, args}, trust)
       when is_list(args) and is_atom(name),
       do: trust and question?(name)

  defp boolean_expression?({name, _meta, args}, trust) when is_atom(name) and is_list(args),
    do: name in @guards or (trust and (question?(name) or guard_name?(name)))

  defp boolean_expression?(_expression, _trust), do: false

  defp question?(name) do
    name
    |> Atom.to_string()
    |> String.ends_with?("?")
  end

  defp guard_name?(name) do
    name
    |> Atom.to_string()
    |> String.starts_with?("is_")
  end

  defp issue(issue_meta, meta, op, literal) do
    format_issue(issue_meta,
      message: "Redundant comparison `#{op} #{literal}`; #{advice(op, literal)}.",
      line_no: meta[:line] || 1
    )
  end

  defp advice(op, literal) when op in [:==, :===],
    do: if(literal, do: "use the boolean expression directly", else: "negate it with `not`")

  defp advice(_op, literal),
    do: if(literal, do: "negate it with `not`", else: "use the boolean expression directly")
end
