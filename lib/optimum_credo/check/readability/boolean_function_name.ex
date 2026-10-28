defmodule OptimumCredo.Check.Readability.BooleanFunctionName do
  @moduledoc """
  Finds `def`/`defp` functions that always return a boolean but whose name does not end in `?`.

  A function is treated as boolean only when every clause with a body ends in an
  expression that is certainly boolean: a literal `true`/`false`, a comparison
  (`==`, `!=`, `===`, `!==`, `<`, `>`, `<=`, `>=`), `in`, `not`, `!`, a Kernel `is_*`
  type check, `and`/`or` whose right side is boolean, or an `if`/`unless`/`case`/`cond`
  whose branches all are. Calls to other functions are never assumed boolean, so
  `def admin(user), do: Roles.admin?(user)` is not reported: only literal-boolean
  bodies are.

  This is a conservative heuristic, not type inference. Functions marked `@impl`,
  macros, and functions whose names already end in `?` or `!` are skipped. Functions are
  grouped by name and arity, and a clause with `rescue`, `catch`, `else`, or `after`
  blocks is never treated as boolean. Boolean
  assigns and variables are not checked.

  ## Parameters

  - `ignore_functions`: function names (atoms or strings) that are exempt.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [ignore_functions: []],
    explanations: [
      check: """
      Functions that return a boolean end in `?`.

      ## Bad

      ```elixir
      def admin(user), do: user.role == :admin
      ```

      ## Good

      ```elixir
      def admin?(user), do: user.role == :admin
      ```

      Only functions whose every clause ends in a certainly-boolean expression are
      reported. Calls to other functions are not assumed to return booleans.
      """,
      params: [ignore_functions: "Function names that are exempt."]
    ]

  alias OptimumCredo.OptimumStructureSupport

  @comparisons [:==, :!=, :===, :!==, :<, :>, :<=, :>=, :in]
  @guards ~w(is_nil is_atom is_binary is_bitstring is_boolean is_float is_function is_integer
             is_list is_map is_number is_pid is_port is_reference is_tuple is_struct
             is_exception is_map_key)a

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    ignored =
      params
      |> Params.get(:ignore_functions, __MODULE__)
      |> OptimumStructureSupport.to_strings()

    source_file
    |> Credo.Code.prewalk(&collect_offenders(&1, &2, ignored))
    |> Enum.sort_by(&elem(&1, 2))
    |> Enum.map(fn {name, arity, line} ->
      format_issue(issue_meta,
        message: "Function #{name}/#{arity} always returns a boolean; end its name with ?.",
        line_no: line
      )
    end)
  end

  defp collect_offenders({:defmodule, _meta, [_name, [do: body]]} = ast, issues, ignored) do
    found = offenders(body, ignored)
    {ast, Enum.reverse(found, issues)}
  end

  defp collect_offenders(ast, issues, _ignored), do: {ast, issues}

  defp definitions(body) do
    body
    |> OptimumStructureSupport.statements()
    |> OptimumStructureSupport.functions()
    |> Enum.filter(&(&1.kind in [:def, :defp] and not &1.impl?))
    |> Enum.group_by(&{&1.name, &1.arity})
  end

  defp offenders(body, ignored) do
    body
    |> definitions()
    |> Enum.filter(fn {{name, _arity}, clauses} -> offender?(name, clauses, ignored) end)
    |> Enum.map(fn {{name, arity}, [first | _tail]} -> {name, arity, first.line} end)
  end

  defp offender?(name, clauses, ignored) do
    string = Atom.to_string(name)
    with_body = Enum.filter(clauses, & &1.body?)

    not String.ends_with?(string, ["?", "!"]) and string not in ignored and with_body != [] and
      Enum.all?(with_body, &(not &1.extra_blocks? and boolean?(&1.body)))
  end

  defp boolean?(value) when is_boolean(value), do: true

  defp boolean?({:__block__, _meta, [_head | _tail] = exprs}) do
    exprs
    |> List.last()
    |> boolean?()
  end

  defp boolean?({operator, _meta, [_left, _right]}) when operator in @comparisons, do: true
  defp boolean?({operator, _meta, [_operand]}) when operator in [:not, :!], do: true

  defp boolean?({operator, _meta, [_left, right]}) when operator in [:and, :or],
    do: boolean?(right)

  defp boolean?({name, _meta, [_head | _tail]}) when name in @guards, do: true

  defp boolean?({name, _meta, [_condition, options]})
       when name in [:if, :unless] and is_list(options),
       do:
         Keyword.has_key?(options, :else) and boolean?(options[:do]) and boolean?(options[:else])

  defp boolean?({:case, _meta, [_subject, [do: clauses]]}), do: clauses_boolean?(clauses)
  defp boolean?({:cond, _meta, [[do: clauses]]}), do: clauses_boolean?(clauses)
  defp boolean?(_other), do: false

  defp clauses_boolean?([_head | _tail] = clauses),
    do: Enum.all?(clauses, fn {:->, _meta, [_head, body]} -> boolean?(body) end)

  defp clauses_boolean?(_clauses), do: false
end
