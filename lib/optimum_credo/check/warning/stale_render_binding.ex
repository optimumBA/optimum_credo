defmodule OptimumCredo.Check.Warning.StaleRenderBinding do
  @moduledoc """
  Finds assertions on a rendered-HTML binding that was captured before a LiveView
  interaction and never rebound.

  Within one test body (top-level statements, in order) the check tracks variables bound
  from `live/2`-style producers (`{:ok, view, html} = live(..)` tracks `html`, never the
  `view`) and `render*` producers (`html = render(view)`), marks them stale once an
  interaction (`render_click`, `render_submit`, `send(view.pid, ..)`, ...) runs, and reports
  a later `assert`/`refute` that reads a stale variable. Variables bound inside the
  assertion itself (`fn html -> .. end`, `for html <- ..`, `assert html = render(view)`)
  are not reads, and comparing a stale snapshot with a fresher one
  (`assert before != after`) is accepted. Assertions nested in `Enum.each`/`for` are
  checked against the state before that statement. Producers and interactions are
  recognised as local/imported calls or remote calls on `modules`. It cannot see control
  flow, rebinding in branches or helpers; `send(self(), ..)` is not an interaction.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [
      producers: [
        :live,
        :live_isolated,
        :render,
        :render_component,
        :render_click,
        :render_submit,
        :render_change,
        :render_keydown,
        :render_keyup,
        :render_blur,
        :render_focus,
        :render_hook,
        :render_async,
        :render_patch,
        :follow_redirect
      ],
      interactions: [
        :render_click,
        :render_submit,
        :render_change,
        :render_keydown,
        :render_keyup,
        :render_blur,
        :render_focus,
        :render_hook,
        :render_upload,
        :render_async,
        :render_patch,
        :follow_redirect,
        :send
      ],
      modules: [Phoenix.LiveViewTest, Phoenix.ConnTest, Kernel]
    ],
    explanations: [
      check: """
      An assertion on HTML captured before an interaction can pass (or fail) for the wrong
      reason. Re-render or bind the interaction result.

      Bad:

          {:ok, view, html} = live(conn, ~p"/")
          view |> element("button") |> render_click()
          assert html =~ "clicked"

      Good:

          html = view |> element("button") |> render_click()
          assert html =~ "clicked"
      """,
      params: [
        producers: "Function names whose result is rendered HTML worth tracking.",
        interactions: "Function names that change the rendered page.",
        modules: "Modules whose remote calls count as producers/interactions (locals always do)."
      ]
    ]

  alias OptimumCredo.TestsSupport

  @comparisons [:==, :===, :!=, :!==]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    if TestsSupport.test_file?(source_file) do
      issue_meta = IssueMeta.for(source_file, params)

      config = %{
        producers: Params.get(params, :producers, __MODULE__),
        interactions: Params.get(params, :interactions, __MODULE__),
        modules:
          params
          |> Params.get(:modules, __MODULE__)
          |> Enum.map(&TestsSupport.normalize_module/1)
      }

      source_file
      |> TestsSupport.ast()
      |> TestsSupport.blocks([:test])
      |> Enum.flat_map(fn test ->
        test.body
        |> TestsSupport.statements()
        |> scan(%{tracked: MapSet.new(), stale: MapSet.new()}, [], test.env, config)
        |> Enum.reverse()
      end)
      |> Enum.map(fn {var, line} ->
        format_issue(issue_meta,
          message:
            "Assertion reads `#{var}`, rendered before an interaction and not rebound since.",
          line_no: line,
          trigger: to_string(var)
        )
      end)
    else
      []
    end
  end

  defp scan([], _state, issues, _env, _config), do: issues

  defp scan([statement | rest], state, issues, env, config) do
    interaction? = calls?(statement, env, config.interactions, config, true)

    issues =
      statement
      |> assertions(interaction?)
      |> Enum.flat_map(&stale_reads(&1, state))
      |> Enum.reduce(issues, &[&1 | &2])

    scan(rest, update(statement, state, interaction?, env, config), issues, env, config)
  end

  # Top-level assertions always; nested ones only when the statement runs no interaction itself.
  defp assertions({name, _meta, [_head | _tail]} = statement, _interaction?)
       when name in [:assert, :refute],
       do: [statement]

  defp assertions(_statement, true), do: []

  defp assertions(statement, false) do
    statement
    |> TestsSupport.walk([], fn
      {name, _meta, [_head | _tail]} = node, acc when name in [:assert, :refute] -> [node | acc]
      _node, acc -> acc
    end)
    |> Enum.reverse()
  end

  defp stale_reads({_name, meta, [arg | _tail]}, state) do
    {comparison_pairs?, reads} = assertion_reads(arg)

    stale =
      reads
      |> Enum.filter(&MapSet.member?(state.stale, &1))
      |> Enum.uniq()

    if stale == [] or compares_snapshots?(arg, state, comparison_pairs?),
      do: [],
      else: Enum.map(stale, &{&1, meta[:line] || 1})
  end

  # `assert pattern = rhs` binds `pattern`: only the right side (and pins) are reads.
  defp assertion_reads({:=, _meta, [pattern, rhs]}), do: {false, pins(pattern) ++ reads(rhs)}
  defp assertion_reads(arg), do: {true, reads(arg)}

  defp compares_snapshots?(_arg, _state, false), do: false

  defp compares_snapshots?(arg, state, true) do
    tracked = MapSet.union(state.tracked, state.stale)

    TestsSupport.walk(arg, false, fn
      {op, _meta, [left, right]}, acc when op in @comparisons ->
        acc or snapshot_comparison?(left, right, tracked)

      _node, acc ->
        acc
    end)
  end

  defp snapshot_comparison?(left, right, tracked) do
    reads(left) -- reads(right) != [] and tracked_read?(left, tracked) and
      tracked_read?(right, tracked)
  end

  defp tracked_read?(side, tracked) do
    side
    |> reads()
    |> Enum.any?(&(&1 in tracked))
  end

  defp bind_html_vars(pattern, tracked) do
    pattern
    |> html_vars()
    |> MapSet.new()
    |> MapSet.union(tracked)
  end

  defp update(statement, state, interaction?, env, config) do
    stale =
      if interaction?, do: MapSet.union(state.stale, state.tracked), else: state.stale

    case match_parts(statement) do
      {pattern, rhs} ->
        rebound = pattern_vars(pattern)

        tracked =
          if calls?(rhs, env, config.producers, config, false),
            do: bind_html_vars(pattern, state.tracked),
            else: MapSet.difference(state.tracked, MapSet.new(rebound))

        %{tracked: tracked, stale: MapSet.difference(stale, MapSet.new(rebound))}

      nil ->
        %{state | stale: stale}
    end
  end

  defp match_parts({:=, _meta, [pattern, rhs]}), do: {pattern, rhs}

  defp match_parts({name, _meta, [{:=, _meta2, [pattern, rhs]}]}) when name in [:assert, :refute],
    do: {pattern, rhs}

  defp match_parts(_statement), do: nil

  # `{:ok, view, html} = live(..)` tracks only `html`; a plain variable tracks itself;
  # other shapes (`{:ok, view}`, maps) are not rendered HTML.
  defp html_vars({:{}, _meta, [:ok, _view, last]}), do: pattern_vars(last)

  defp html_vars({name, _meta, context}) when is_atom(name) and is_atom(context),
    do: pattern_vars({name, [], context})

  defp html_vars(_pattern), do: []

  defp pattern_vars(ast) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {:^, _meta, _args}, acc ->
          {nil, acc}

        {name, _meta, context} = node, acc when is_atom(name) and is_atom(context) ->
          {node, keep(name, acc)}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  defp pins(ast) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {:^, _meta, [{name, _tuple_meta, context}]} = node, acc
        when is_atom(name) and is_atom(context) ->
          {node, keep(name, acc)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp keep(name, acc) do
    string = Atom.to_string(name)

    if String.starts_with?(string, "_") or name in [:__MODULE__, :__ENV__, :__CALLER__],
      do: acc,
      else: [name | acc]
  end

  # Variables read by an expression, minus those a nested clause or generator binds itself.
  defp reads(ast) do
    ast
    |> do_reads()
    |> Enum.uniq()
  end

  defp do_reads({:quote, _meta, _args}), do: []

  defp do_reads({:^, _meta, [{name, _tuple_meta, context}]})
       when is_atom(name) and is_atom(context),
       do: keep(name, [])

  # Inside a block, a variable assigned by an earlier statement is local, not a read of ours.
  defp do_reads({:__block__, _meta, statements}) when is_list(statements) do
    {_bound, reads} =
      Enum.reduce(statements, {[], []}, fn statement, {bound, reads} ->
        fresh =
          statement
          |> do_reads()
          |> Enum.reject(&(&1 in bound))

        {assigned(statement) ++ bound, fresh ++ reads}
      end)

    reads
  end

  defp do_reads({:=, _meta, [pattern, rhs]}), do: pins(pattern) ++ do_reads(rhs)

  defp do_reads({:->, _meta, [params, body]}) do
    {patterns, guards} = split_guards(params)
    bound = pattern_vars(patterns)
    Enum.reject(do_reads(guards) ++ do_reads(body), &(&1 in bound))
  end

  defp do_reads({construct, _meta, args}) when construct in [:for, :with] and is_list(args) do
    bound =
      args
      |> generator_patterns()
      |> pattern_vars()

    args
    |> do_reads()
    |> Enum.reject(&(&1 in bound))
  end

  defp do_reads({name, _meta, context}) when is_atom(name) and is_atom(context),
    do: keep(name, [])

  defp do_reads({form, _meta, args}) when is_list(args),
    do: do_reads(form) ++ Enum.flat_map(args, &do_reads/1)

  defp do_reads({left, right}), do: do_reads(left) ++ do_reads(right)
  defp do_reads(list) when is_list(list), do: Enum.flat_map(list, &do_reads/1)
  defp do_reads(_leaf), do: []

  defp assigned({:=, _meta, [pattern, rhs]}), do: pattern_vars(pattern) ++ assigned(rhs)
  defp assigned(_statement), do: []

  defp split_guards([{:when, _meta, args}]) do
    {patterns, [guard]} = Enum.split(args, -1)
    {patterns, guard}
  end

  defp split_guards(params), do: {params, []}

  defp generator_patterns(args) do
    for {:<-, _meta, [pattern, _expr]} <- args, do: pattern
  end

  defp calls?(ast, env, names, config, interaction?) do
    TestsSupport.walk_env(
      ast,
      false,
      fn node, env, acc ->
        {:cont,
         acc or
           node
           |> TestsSupport.call(env)
           |> tracked_call?(names, config, interaction?)}
      end,
      env
    )
  end

  defp tracked_call?(nil, _names, _config, _interaction?), do: false

  defp tracked_call?(call, names, config, interaction?) do
    call.fun in names and (call.kind == :local or call.module in config.modules) and
      not (interaction? and self_send?(call))
  end

  defp self_send?(%{fun: :send, args: [{:self, _meta, []} | _tail]}), do: true
  defp self_send?(_call), do: false
end
