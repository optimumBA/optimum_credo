defmodule OptimumCredo.Check.Warning.EnvVarWithoutFailure do
  @moduledoc """
  Finds `System.get_env("VAR")` (no default) in the production branch of
  `config/runtime.exs` whose `nil` result is silently used.

  A missing required variable should stop the boot with a clear message, not produce a
  `nil` setting that fails later. Use `System.fetch_env!/1`, or raise explicitly.

  The check only reads `config/runtime.exs` and only inside the `do` branch of an
  `if` whose condition implies production (`config_env() == :prod`, `config_env() in [:prod]`,
  or either of those joined to other tests with `and`) and `case config_env() do :prod -> ... end`.
  `if config_env() != :prod`, `unless` and `or` conditions are not production-only and are
  skipped. A key that is not a string literal is reported without a name.

  A `System.get_env/1` call is considered handled when it is:

  - the left side of `||` (`System.get_env("X") || raise "missing X"`, or a fallback);
  - the subject of `case`/`if`/`unless` (or piped into `case`) whose code contains `raise`;
  - the condition of `if`/`unless` (a presence test for an optional feature);
  - assigned to a variable that a later statement in the same block uses together with `raise`,
    or tests in the condition of an `if`/`unless` (`if host = System.get_env("HOST")` too);
  - compared (`System.get_env("DEBUG") == "true"`) or tested with `is_nil/1`/`not`/`!`, which
    cannot leak a `nil` setting;
  - an argument of, or piped into, a bang function (`Base.decode64!/1`) or
    `String.to_integer/1` / `String.to_float/1`, which crash on `nil`.

  `System.get_env/2` with a default is not inspected (see `KogenCredo.Check.Warning.RuntimeEnvDevDefault`).

  ## Parameters

  - `optional_vars`: variable names that are legitimately optional. Defaults to
    `["DNS_CLUSTER_QUERY"]`, the optional variable `mix phx.new` generates (`nil` disables
    clustering). Setting `optional_vars` replaces that default, so repeat it if you still want it.

  Wrappers around `System.get_env` and `nil` handling in later functions are not followed.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [optional_vars: ["DNS_CLUSTER_QUERY"]],
    explanations: [
      check: """
      Fail loudly on missing production environment variables.

      ## Bad

      ```elixir
      if config_env() == :prod do
        client_id = System.get_env("GITHUB_CLIENT_ID")
      end
      ```

      ## Good

      ```elixir
      if config_env() == :prod do
        client_id = System.fetch_env!("GITHUB_CLIENT_ID")
      end
      ```
      """,
      params: [optional_vars: "Environment variable names that may be unset."]
    ]

  alias OptimumCredo.OptimumDataSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    if OptimumDataSupport.ends_with_path?(source_file, "config/runtime.exs") do
      env_issues(source_file, params)
    else
      []
    end
  end

  defp env_issues(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    optional =
      params
      |> Params.get(:optional_vars, __MODULE__)
      |> Enum.map(&to_string/1)

    source_file
    |> Credo.SourceFile.ast()
    |> prod_bodies()
    |> Enum.flat_map(&unhandled(&1, optional))
    |> Enum.uniq_by(fn {_key, meta} -> {meta[:line], meta[:column]} end)
    |> Enum.map(fn {key, meta} ->
      format_issue(issue_meta,
        message:
          "#{describe(key)} in the prod config can return nil; " <>
            "if required, use System.fetch_env!/1 or raise; if intentionally optional, list it in optional_vars.",
        trigger: "System.get_env",
        line_no: OptimumDataSupport.line(meta)
      )
    end)
  end

  defp describe(nil), do: "System.get_env/1"
  defp describe(key), do: "System.get_env(#{inspect(key)})"

  # -- production branches ---------------------------------------------------------------

  defp prod_bodies(ast) do
    {_ast, bodies} = Macro.prewalk(ast, [], &collect_prod_body/2)

    Enum.reject(bodies, &is_nil/1)
  end

  defp collect_prod_body({:if, _meta, [condition, options]} = node, acc) when is_list(options) do
    if prod_condition?(condition),
      do: {node, [Keyword.get(options, :do) | acc]},
      else: {node, acc}
  end

  defp collect_prod_body(
         {:case, _meta, [{:config_env, _config_env_meta, _args}, [do: clauses]]} = node,
         acc
       )
       when is_list(clauses) do
    {node, for({:->, _meta, [[:prod], body]} <- clauses, do: body) ++ acc}
  end

  defp collect_prod_body(node, acc), do: {node, acc}

  # True only when the whole condition implies `config_env() == :prod`: `a and prod` is,
  # `a or prod`, `not prod` and `config_env() != :prod` are not.
  defp prod_condition?({:==, _meta, [{:config_env, _config_env_meta, _args}, :prod]}), do: true
  defp prod_condition?({:==, _meta, [:prod, {:config_env, _config_env_meta, _args}]}), do: true
  defp prod_condition?({:===, _meta, [{:config_env, _config_env_meta, _args}, :prod]}), do: true
  defp prod_condition?({:in, _meta, [{:config_env, _config_env_meta, _args}, [:prod]]}), do: true

  defp prod_condition?({operator, _meta, [left, right]}) when operator in [:and, :&&],
    do: prod_condition?(left) or prod_condition?(right)

  defp prod_condition?({operator, _meta, [left, right]}) when operator in [:or, :||],
    do: prod_condition?(left) and prod_condition?(right)

  defp prod_condition?({:__block__, _meta, [condition]}), do: prod_condition?(condition)
  defp prod_condition?(_condition), do: false

  # -- get_env calls ---------------------------------------------------------------------

  defp unhandled(body, optional) do
    handled = handled_positions(body)

    body
    |> get_env_calls()
    |> Enum.reject(fn {key, meta} -> position(meta) in handled or key in optional end)
  end

  defp get_env_calls(body) do
    {_ast, calls} =
      Macro.prewalk(body, [], fn node, acc ->
        case get_env(node) do
          {key, meta} -> {node, [{key, meta} | acc]}
          nil -> {node, acc}
        end
      end)

    Enum.reverse(calls)
  end

  # Only `System.get_env/1`: `get_env/0` returns the whole environment and `get_env/2`
  # has a default. A key that is not a literal is reported as `nil`.
  defp get_env({{:., _meta, [{:__aliases__, _alias_meta, [:System]}, :get_env]}, meta, [key]}),
    do: {if(is_binary(key), do: key), meta}

  defp get_env(_node), do: nil

  defp position(meta), do: {meta[:line], meta[:column]}

  defp handled_positions(body) do
    {_ast, handled} = Macro.prewalk(body, MapSet.new(), &handled_node/2)

    handled
  end

  defp handled_node({:||, _meta, [left, _right]} = node, acc), do: {node, add(acc, [left])}

  defp handled_node({operator, _meta, [subject | _tail]} = node, acc)
       when operator in [:if, :unless],
       do: {node, add(acc, [subject])}

  # Comparisons and nil checks turn a missing value into a plain boolean.
  defp handled_node({operator, _meta, [left, right]} = node, acc)
       when operator in [:==, :!=, :===, :!==, :in, :not_in],
       do: {node, add(acc, [left, right])}

  defp handled_node({operator, _meta, [operand]} = node, acc)
       when operator in [:!, :not, :is_nil, :is_binary],
       do: {node, add(acc, [operand])}

  defp handled_node({:case, _meta, [subject | _tail]} = node, acc),
    do: {node, if(raises?(node), do: add(acc, [subject]), else: acc)}

  defp handled_node({:|>, _meta, [left, right]} = node, acc),
    do: {node, if(handles_piped?(right), do: add(acc, [left]), else: acc)}

  defp handled_node({{:., _meta, _args} = callee, _tuple_meta, args} = node, acc)
       when args != [],
       do: {node, if(crashing_on_nil?(callee), do: add(acc, args), else: acc)}

  defp handled_node({:__block__, _meta, statements} = node, acc),
    do: {node, add(acc, assigned_then_checked(statements))}

  defp handled_node(node, acc), do: {node, acc}

  defp add(acc, nodes) do
    Enum.reduce(nodes, acc, fn node, set ->
      # `if host = System.get_env("HOST")` binds the value it tests.
      node = with {:=, _meta, [_pattern, call]} <- node, do: call

      case get_env(node) do
        {_key, meta} -> MapSet.put(set, position(meta))
        nil -> set
      end
    end)
  end

  defp handles_piped?({:case, _meta, _args} = node), do: raises?(node)

  defp handles_piped?({{:., _meta, _args} = callee, _tuple_meta, _tuple_args}),
    do: crashing_on_nil?(callee)

  defp handles_piped?(_node), do: false

  defp crashing_on_nil?({:., _meta, [{:__aliases__, _alias_meta, [:String]}, function]}),
    do: function in [:to_integer, :to_float]

  defp crashing_on_nil?({:., _meta, [_module, function]}) when is_atom(function) do
    function
    |> Atom.to_string()
    |> String.ends_with?("!")
  end

  defp crashing_on_nil?(_callee), do: false

  defp raises?(ast), do: OptimumDataSupport.contains?(ast, &match?({:raise, _, [_ | _]}, &1))

  # `x = System.get_env("X")` followed by a statement that uses `x` and raises.
  defp assigned_then_checked(statements) do
    statements
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {{:=, _meta, [{variable, _tuple_meta, context}, call]}, index}
      when is_atom(variable) and is_atom(context) ->
        later = Enum.drop(statements, index + 1)
        if Enum.any?(later, &checked_later?(&1, variable)), do: [call], else: []

      _other ->
        []
    end)
  end

  # Used together with `raise`, or as the condition of an `if`/`unless` (a presence test).
  defp checked_later?(statement, variable),
    do: (raises?(statement) and uses?(statement, variable)) or presence_test?(statement, variable)

  defp presence_test?({operator, _meta, [condition | _tail]}, variable)
       when operator in [:if, :unless],
       do: uses?(condition, variable)

  defp presence_test?(_statement, _variable), do: false

  defp uses?(ast, variable) do
    OptimumDataSupport.contains?(
      ast,
      &match?({^variable, _, context} when is_atom(context), &1)
    )
  end
end
