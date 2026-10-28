defmodule OptimumCredo.Check.Warning.SleepInTest do
  @moduledoc """
  Finds `Process.sleep/1`, `:timer.sleep/1` and long `wait`/`wait_until` blocks in test files.

  Heuristic and opt-in: it reads literal call AST in test files only. Remote calls are
  resolved through the `alias`es and `import`s in lexical scope (`alias Process, as: P`,
  `import :timer, only: [sleep: 1]`) and `apply(Process, :sleep, [..])` with literal
  arguments is recognised. Sleeps hidden in helpers or dynamic receivers are not seen.
  `sleep(:infinity)` (parking a helper process) is not a delay and is ignored.
  Calls inside `quote` are ignored. Files tagged with `@moduletag :timing` are exempt.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [
      functions: [{Process, :sleep}, {:timer, :sleep}],
      wait_functions: [:wait, :wait_until],
      max_wait_block_lines: 5,
      exempt_moduletag: :timing
    ],
    explanations: [
      check: """
      Sleeping in tests slows the suite and hides races. Synchronise on a message
      (`assert_receive`) or an observable state change instead.

      Bad:

          Process.sleep(200)
          assert render(view) =~ "done"

      Good:

          assert_receive {:done, _}

      Genuine timer/debounce tests can be tagged with `@moduletag :timing`.
      This is a static heuristic over literal calls in test files.
      """,
      params: [
        functions: "`{module, function}` pairs treated as sleeps.",
        wait_functions:
          "Function names (local or remote) whose `do`/`fn` block is flagged when longer than `max_wait_block_lines`.",
        max_wait_block_lines: "Longest tolerated `wait` block, in lines.",
        exempt_moduletag: "A `@moduletag` atom that exempts the whole file (false disables)."
      ]
    ]

  alias OptimumCredo.TestsSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    ast = TestsSupport.ast(source_file)
    exempt = Params.get(params, :exempt_moduletag, __MODULE__)

    if TestsSupport.test_file?(source_file) and not TestsSupport.moduletag?(ast, exempt) do
      sleep_issues(ast, IssueMeta.for(source_file, params), params)
    else
      []
    end
  end

  defp sleep_issues(ast, issue_meta, params) do
    functions =
      params
      |> Params.get(:functions, __MODULE__)
      |> Enum.map(fn {module, fun} -> {TestsSupport.normalize_module(module), fun} end)

    waits = Params.get(params, :wait_functions, __MODULE__)
    max_lines = Params.get(params, :max_wait_block_lines, __MODULE__)
    polling = polling_helper_lines(ast, functions)

    ast
    |> TestsSupport.walk_env([], fn node, env, acc ->
      {:cont, check(node, TestsSupport.call(node, env), acc, {functions, waits, max_lines})}
    end)
    |> Enum.reverse()
    |> Enum.reject(fn {_message, line} -> MapSet.member?(polling, line) end)
    |> Enum.map(fn {message, line} ->
      format_issue(issue_meta, message: message, line_no: line)
    end)
  end

  defp check(_node, nil, acc, _config), do: acc

  defp check(node, call, acc, {functions, waits, max_lines}) do
    line = call.meta[:line] || 1

    cond do
      {call.module, call.fun} in functions ->
        if call.args == [] or not infinity?(hd(call.args)) do
          [
            {"Avoid #{call.module}.#{call.fun}/1 in tests; synchronise on a message instead.",
             line}
            | acc
          ]
        else
          acc
        end

      call.fun in waits and long_block?(call.args, node, max_lines) ->
        [
          {"`#{call.fun}` wraps more than #{max_lines} lines; prefer assert_receive or a direct assertion.",
           line}
          | acc
        ]

      true ->
        acc
    end
  end

  # A sleep inside a recursive `def`/`defp` is the back-off of a bounded polling helper
  # (`if not_ready?(), do: (sleep(50); wait(retries - 1))`), not a fixed wait for a race.
  defp polling_helper_lines(ast, functions) do
    {_ast, lines} =
      Macro.prewalk(ast, MapSet.new(), fn
        {kind, _meta, [head, body]} = node, acc when kind in [:def, :defp] ->
          {node, collect_polling(head, body, functions, acc)}

        node, acc ->
          {node, acc}
      end)

    lines
  end

  defp collect_polling(head, body, functions, acc) do
    name = function_name(head)
    names = for {_module, fun} <- functions, do: fun

    {_body, {recursive?, sleeps}} =
      Macro.prewalk(body, {false, []}, &track_polling(&1, &2, name, names))

    if recursive?, do: Enum.reduce(sleeps, acc, &MapSet.put(&2, &1)), else: acc
  end

  defp track_polling({name, _meta, args} = node, {_key, sleeps}, name, _names)
       when is_list(args) and name != nil,
       do: {node, {true, sleeps}}

  defp track_polling(
         {{:., _meta, [_module, fun]}, meta, _args} = node,
         {rec, sleeps},
         _name,
         names
       ),
       do: {node, {rec, if(fun in names, do: [meta[:line] | sleeps], else: sleeps)}}

  defp track_polling(node, state, _name, _names), do: {node, state}

  defp function_name({:when, _meta, [head | _tail]}), do: function_name(head)
  defp function_name({name, _meta, args}) when is_atom(name) and is_list(args), do: name
  defp function_name(_head), do: nil

  defp infinity?(arg), do: match?({:ok, :infinity, _line}, TestsSupport.literal(arg))

  defp long_block?(args, node, max_lines) do
    block? =
      Enum.any?(args, fn
        {:fn, _meta, _args} ->
          true

        options when is_list(options) ->
          Keyword.keyword?(options) and Keyword.has_key?(options, :do)

        _ignored ->
          false
      end)

    {first, last} = TestsSupport.line_span(node)
    block? and last - first + 1 > max_lines
  end
end
