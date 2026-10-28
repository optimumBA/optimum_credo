defmodule OptimumCredo.Check.Readability.MaybePrefix do
  @moduledoc """
  Finds functions that conditionally pass their first argument through unchanged but are
  not named `maybe_*`.

  A function is reported when, across its clauses and the branches of a final
  `if`/`unless`/`case`/`cond`, at least one result is exactly the first parameter
  variable and at least one other result is a function call or pipeline. That shape,
  `def apply_filter(query, nil), do: query`, is what the `maybe_` prefix signals.

  This is a conservative, opt-in heuristic. It cannot tell whether the call has side
  effects, so a pure normalizer with the same shape is also reported. Functions
  marked `@impl`, names ending in `?`, names starting with an accepted prefix, and
  macros are skipped. Function plugs, whose `(conn, opts)` signature and name are fixed by
  the Plug contract and by `plug :name`, are skipped too, as is a pass-through clause that
  only accepts a value already of the target type (`defp to_integer(n) when is_integer(n),
  do: n` next to a parsing clause), which is type dispatch rather than a conditional action. Functions are grouped by name and arity, recursive calls do not
  count as the acting call, and clauses with `rescue`, `catch`, `else`, or `after` blocks
  are not analysed. It does not check that `maybe_` functions are actually conditional.

  ## Parameters

  - `prefix`: the required prefix (default `"maybe_"`).
  - `allowed_prefixes`: additional accepted prefixes such as `["ensure_"]`.
  - `ignore_functions`: function names (atoms or strings) that are exempt.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [prefix: "maybe_", allowed_prefixes: [], ignore_functions: []],
    explanations: [
      check: """
      Functions that may or may not act on their first argument start with `maybe_`.

      ## Bad

      ```elixir
      defp load_user(socket, nil), do: socket
      defp load_user(socket, id), do: assign(socket, :user, Accounts.get_user(id))
      ```

      ## Good

      ```elixir
      defp maybe_load_user(socket, nil), do: socket
      defp maybe_load_user(socket, id), do: assign(socket, :user, Accounts.get_user(id))
      ```

      The check detects the shape (the first argument returned unchanged on one path,
      a call on another); it cannot tell whether the call has side effects.
      """,
      params: [
        prefix: "Required name prefix.",
        allowed_prefixes: "Additional accepted prefixes.",
        ignore_functions: "Function names that are exempt."
      ]
    ]

  alias OptimumCredo.OptimumStructureSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    prefix = Params.get(params, :prefix, __MODULE__)

    accepted = [
      prefix
      | params
        |> Params.get(:allowed_prefixes, __MODULE__)
        |> OptimumStructureSupport.to_strings()
    ]

    ignored =
      params
      |> Params.get(:ignore_functions, __MODULE__)
      |> OptimumStructureSupport.to_strings()

    source_file
    |> Credo.Code.prewalk(&collect_offenders(&1, &2, accepted, ignored))
    |> Enum.sort_by(&elem(&1, 2))
    |> Enum.map(fn {name, _arity, line} ->
      format_issue(issue_meta,
        message:
          "Function #{name} conditionally returns its first argument unchanged; " <>
            "name it #{prefix}#{name}.",
        line_no: line
      )
    end)
  end

  defp collect_offenders(
         {:defmodule, _meta, [_name, [do: body]]} = ast,
         issues,
         accepted,
         ignored
       ) do
    found = offenders(body, accepted, ignored)
    {ast, Enum.reverse(found, issues)}
  end

  defp collect_offenders(ast, issues, _accepted, _ignored), do: {ast, issues}

  defp definitions(body) do
    body
    |> OptimumStructureSupport.statements()
    |> OptimumStructureSupport.functions()
    |> Enum.filter(&(&1.kind in [:def, :defp] and not &1.impl?))
    |> Enum.group_by(&{&1.name, &1.arity})
  end

  defp offenders(body, accepted, ignored) do
    body
    |> definitions()
    |> Enum.filter(fn {{name, _arity}, clauses} ->
      offender?(name, clauses, accepted, ignored)
    end)
    |> Enum.map(fn {{name, arity}, [first | _tail]} -> {name, arity, first.line} end)
  end

  defp offender?(name, clauses, accepted, ignored) do
    string = Atom.to_string(name)

    if String.ends_with?(string, "?") or string in ignored or plug_signature?(clauses) or
         Enum.any?(accepted, &String.starts_with?(string, &1)) do
      false
    else
      results = Enum.flat_map(clauses, &results(&1, name))
      Enum.any?(results, &(&1 == :passthrough)) and Enum.any?(results, &(&1 == :call))
    end
  end

  # The Plug contract fixes the `(conn, opts)` signature, and `plug :name` fixes the name.
  defp plug_signature?(clauses) do
    Enum.any?(clauses, fn
      %{args: [{:conn, _conn_meta, conn_context}, {opts, _opts_meta, opts_context}]}
      when is_atom(conn_context) and opts in [:opts, :_opts] and is_atom(opts_context) ->
        true

      _clause ->
        false
    end)
  end

  # Classifies each possible result of a clause as :passthrough, :call or :other.
  defp results(
         %{args: [first | _tail], body?: true, extra_blocks?: false, body: body} = clause,
         name
       ) do
    case bound_variable(first) do
      nil ->
        []

      variable ->
        body
        |> terminals()
        |> Enum.map(&classify(&1, variable, name, clause))
    end
  end

  defp results(_clause, _name), do: []

  defp bound_variable({name, _meta, context}) when is_atom(name) and is_atom(context) do
    if underscored?(name), do: nil, else: name
  end

  defp bound_variable({:=, _meta, [left, right]}),
    do: bound_variable(right) || bound_variable(left)

  defp bound_variable(_other), do: nil

  defp underscored?(name) do
    name
    |> Atom.to_string()
    |> String.starts_with?("_")
  end

  defp terminals({:__block__, _meta, [_head | _tail] = exprs}) do
    exprs
    |> List.last()
    |> terminals()
  end

  defp terminals({name, _meta, [_condition, options]})
       when name in [:if, :unless] and is_list(options),
       do: terminals(options[:do]) ++ else_terminals(options)

  defp terminals({:case, _meta, [_subject, [do: clauses]]}), do: clause_terminals(clauses)
  defp terminals({:cond, _meta, [[do: clauses]]}), do: clause_terminals(clauses)
  defp terminals(other), do: [other]

  defp else_terminals(options) do
    options
    |> Keyword.get(:else)
    |> terminals()
  end

  defp clause_terminals(clauses) when is_list(clauses) do
    Enum.flat_map(clauses, fn
      {:->, _meta, [_head, body]} -> terminals(body)
      _other -> []
    end)
  end

  defp clause_terminals(_clauses), do: []

  defp classify({name, _meta, context}, variable, _function, clause)
       when name == variable and is_atom(context) do
    if type_guarded?(clause, variable), do: :other, else: :passthrough
  end

  defp classify({:|>, _meta, _args}, _variable, _function, _clause), do: :call

  defp classify({{:., _dot, _target}, _meta, args}, _variable, _function, _clause)
       when is_list(args),
       do: :call

  # A recursive call is the function continuing its own work, not a conditional action.
  defp classify({function, _meta, args}, _variable, function, _clause) when is_list(args),
    do: :other

  defp classify({name, _meta, args}, _variable, _function, _clause)
       when is_atom(name) and is_list(args) do
    if name in [:raise, :throw, :exit, :{}, :%{}, :%, :<<>>, :__block__, :fn, :&],
      do: :other,
      else: :call
  end

  defp classify(_other, _variable, _function, _clause), do: :other

  # `when is_integer(arg)` marks the clause that already has the target type.
  defp type_guarded?(%{code: [guards | _tail]}, variable) do
    guards
    |> List.wrap()
    |> Enum.flat_map(&guard_tests/1)
    |> Enum.any?(fn
      {test, _meta, [{^variable, _var_meta, context}]} when is_atom(context) ->
        test
        |> Atom.to_string()
        |> String.starts_with?("is_")

      _other ->
        false
    end)
  end

  defp guard_tests({op, _meta, [left, right]}) when op in [:and, :or, :&&, :||],
    do: guard_tests(left) ++ guard_tests(right)

  defp guard_tests(guard), do: [guard]
end
