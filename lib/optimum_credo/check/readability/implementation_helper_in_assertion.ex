defmodule OptimumCredo.Check.Readability.ImplementationHelperInAssertion do
  @moduledoc """
  Finds assertions whose expected side is computed with the implementation's own
  formatting helper.

  Watched modules: the module under test inferred from the test module name
  (`Foo.BarTest` -> `Foo.Bar`, `FooWeb.BarLiveTest` -> `FooWeb.BarLive`), the configured
  `modules`, and (unless `watch_namespace: false`) any other module resolved through the
  file's aliases/imports that shares the test's application namespace (`MyApp`/`MyAppWeb`),
  except fixtures, factories, cases and support modules.

  In `assert/refute lhs OP rhs` with `==`, `===`, `!=`, `!==`, `=~`, a call on a watched
  module to a function matching `helper_pattern` is reported when it sits on the right-hand
  side, or reaches the assertion through a variable assigned from such a call in the same
  test (`expected = Money.format(5)`; for that dataflow only the module under test and the
  configured `modules` count, not the wider namespace, because `html = Driver.render_html(..)`
  is usually the actual value). A helper called directly on the left-hand side is the
  function under test and is fine, as is a right-hand helper compared against a literal on
  the left (`assert "$5.00" == Money.format(5)`). Calls are resolved through `alias`/`import`
  in lexical scope. Heuristic: dataflow is limited to plain variable assignments.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [
      helper_pattern: "^(format|humanize|display|label|render|title|slug|translate|to_)",
      modules: [],
      watch_namespace: true
    ],
    explanations: [
      check: """
      A test that builds its expectation with the same function the implementation uses
      proves nothing. Hardcode the expected value.

      Bad:   assert html =~ Money.format(price)
      Good:  assert html =~ "$5.00"
      """,
      params: [
        helper_pattern: "Regex source for function names that format/compute expectations.",
        modules: "Extra implementation modules (atoms or strings) to watch.",
        watch_namespace:
          "Also watch aliased/imported modules sharing the test module's application namespace."
      ]
    ]

  alias OptimumCredo.TestsSupport

  @comparisons [:==, :===, :!=, :!==, :=~]
  @support_suffixes ~w(Fixtures Factory Factories Case Support Mock Test)

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    if TestsSupport.test_file?(source_file) do
      ast = TestsSupport.ast(source_file)
      issue_meta = IssueMeta.for(source_file, params)
      config = config(ast, params)

      ast
      |> TestsSupport.walk_env([], &scan(&1, &2, &3, config))
      |> Enum.reverse()
      |> Enum.map(fn {call, line} ->
        format_issue(issue_meta,
          message:
            "Assertion builds its expectation with implementation helper #{call}; hardcode the expected value.",
          line_no: line
        )
      end)
    else
      []
    end
  end

  defp config(ast, params) do
    %{
      pattern:
        params
        |> Params.get(:helper_pattern, __MODULE__)
        |> TestsSupport.compile_pattern(),
      watched: watched(ast, params)
    }
  end

  defp scan({:test, _meta, [_name | _tail] = args}, env, acc, config) do
    case List.last(args) do
      [{:do, body} | _tail] -> {:skip, check_scope(body, env, config, acc)}
      _other -> {:cont, acc}
    end
  end

  defp scan({name, _meta, [_head | _tail]} = node, env, acc, config)
       when name in [:assert, :refute] do
    {:cont, check_assertion(node, env, config, MapSet.new(), acc)}
  end

  defp scan(_node, _env, acc, _config), do: {:cont, acc}

  # One test body: variables assigned from a helper call, then every assertion in it.
  defp check_scope(body, env, config, acc) do
    derived =
      TestsSupport.walk_env(
        body,
        MapSet.new(),
        fn
          {:=, _meta, [{name, _tuple_meta, context}, expr]}, env, derived
          when is_atom(name) and is_atom(context) ->
            if helper_call(expr, env, config, true),
              do: {:cont, MapSet.put(derived, name)},
              else: {:cont, derived}

          _node, _env, derived ->
            {:cont, derived}
        end,
        env
      )

    TestsSupport.walk_env(
      body,
      acc,
      fn
        {name, _meta, [_head | _tail]} = node, env, acc when name in [:assert, :refute] ->
          {:cont, check_assertion(node, env, config, derived, acc)}

        _node, _env, acc ->
          {:cont, acc}
      end,
      env
    )
  end

  defp check_assertion({_name, meta, [{op, _meta, [lhs, rhs]}]}, env, config, derived, acc)
       when op in @comparisons do
    found =
      cond do
        literal?(lhs) -> nil
        call = helper_call(rhs, env, config) -> call
        found = derived_read(rhs, derived) -> found
        true -> nil
      end

    if found, do: [{found, meta[:line] || 1} | acc], else: acc
  end

  defp check_assertion(_node, _env, _config, _derived, acc), do: acc

  defp derived_read(expr, derived) do
    TestsSupport.walk(expr, nil, fn
      {name, _meta, context}, nil when is_atom(name) and is_atom(context) ->
        if MapSet.member?(derived, name), do: "`#{name}` (assigned from a helper)", else: nil

      _node, found ->
        found
    end)
  end

  defp literal?(node) do
    match?({:ok, _value, _line}, TestsSupport.literal(node)) or compound_literal?(node)
  end

  defp compound_literal?(list) when is_list(list), do: Enum.all?(list, &literal?/1)
  defp compound_literal?({left, right}), do: literal?(left) and literal?(right)

  defp compound_literal?({kind, _meta, items}) when kind in [:{}, :%{}],
    do: Enum.all?(items, &literal?/1)

  defp compound_literal?({:<<>>, _meta, [text]}) when is_binary(text), do: true
  defp compound_literal?(_other), do: false

  defp helper_call(expr, env, config, strict? \\ false) do
    TestsSupport.walk_env(
      expr,
      nil,
      fn node, env, found ->
        case found ||
               node
               |> TestsSupport.call(env)
               |> match_helper(config, strict?) do
          nil -> {:cont, nil}
          found -> {:skip, found}
        end
      end,
      env
    )
  end

  defp match_helper(nil, _config, _strict?), do: nil

  defp match_helper(%{module: nil}, _config, _strict?), do: nil

  defp match_helper(%{module: module, fun: fun}, %{watched: watched, pattern: pattern}, strict?) do
    if watched?(module, watched, strict?) and Regex.match?(pattern, Atom.to_string(fun)),
      do: "#{module}.#{fun}"
  end

  defp watched(ast, params) do
    subjects =
      ast
      |> TestsSupport.walk([], fn
        {:defmodule, _meta, [{:__aliases__, _alias_meta, segments} | _tail]}, acc ->
          if Enum.all?(segments, &is_atom/1),
            do: [TestsSupport.join_name(segments) | acc],
            else: acc

        _node, acc ->
          acc
      end)
      |> Enum.flat_map(&subject/1)

    explicit =
      params
      |> Params.get(:modules, __MODULE__)
      |> Enum.map(&TestsSupport.normalize_module/1)

    %{
      modules: subjects ++ explicit,
      namespaces:
        if(Params.get(params, :watch_namespace, __MODULE__),
          do: namespaces(subjects),
          else: []
        )
    }
  end

  defp namespaces(subjects) do
    subjects
    |> Enum.map(&namespace/1)
    |> Enum.uniq()
  end

  defp subject(module) do
    segments = String.split(module, ".")
    last = List.last(segments)

    if String.ends_with?(last, "Test") and last != "Test" do
      trimmed = String.replace_suffix(last, "Test", "")

      [
        segments
        |> List.replace_at(-1, trimmed)
        |> Enum.join(".")
      ]
    else
      []
    end
  end

  defp namespace(module) do
    module
    |> String.split(".")
    |> hd()
    |> String.replace_suffix("Web", "")
  end

  defp watched?(module, %{modules: modules, namespaces: namespaces}, strict?) do
    module in modules or
      (not strict? and namespaces != [] and in_namespace?(module, namespaces) and
         not support?(module))
  end

  defp in_namespace?(":" <> _erlang, _namespaces), do: false

  defp in_namespace?(module, namespaces) do
    [root | _tail] = String.split(module, ".")
    String.replace_suffix(root, "Web", "") in namespaces
  end

  defp support?(module) do
    segments = String.split(module, ".")
    last = List.last(segments)

    Enum.any?(@support_suffixes, &String.ends_with?(last, &1)) or
      Enum.any?(segments, &(&1 in ["Support", "Test", "Fixtures", "Factory"]))
  end
end
