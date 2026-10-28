defmodule OptimumCredo.Check.Warning.TestWithoutAssertion do
  @moduledoc """
  Finds `test` blocks whose body contains no assertion.

  An assertion is any call named `assert`, `refute` or `assert_*`/`refute_*` (local or
  remote), `catch_error/exit/throw`, `flunk`, an `on_exit` callback, `Mox.verify!`, or (by
  default) a Mox-style `expect`/`expect_once` whose expectation is verified on exit.
  Assertions inside `for`/`Enum.each` count, assertions only in a `setup` block do not, and
  code inside `quote` is ignored.

  `assertion_helpers` only exempt a test whose whole body is a single call to the helper
  (a pipeline ending in it also counts); a helper called among other statements is not an
  assertion. Entries are names (`:check_all`, `"check_all"`), qualified names
  (`"MyApp.Checks.check_all"`) or `{Module, :name}` pairs; qualified entries match the
  receiver after resolving aliases. A test that relies on a raising call can be accepted
  with `treat_bang_call_as_assertion: true`. Static heuristic: assertions performed by
  dynamically dispatched helpers are invisible.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [
      assertion_helpers: [],
      treat_bang_call_as_assertion: false,
      treat_mock_expectations_as_assertions: true,
      treat_match_as_assertion: true
    ],
    explanations: [
      check: """
      A test without an assertion cannot fail for the behaviour it names.

      Bad:

          test "creates" do
            Accounts.create_user(attrs)
          end

      Good:

          test "creates" do
            assert {:ok, _} = Accounts.create_user(attrs)
          end
      """,
      params: [
        assertion_helpers:
          "Helpers (name, `\"Mod.name\"` or `{Mod, :name}`) accepted when the test body is a single call to one.",
        treat_bang_call_as_assertion:
          "When true, any call to a `name!` function counts as an assertion.",
        treat_mock_expectations_as_assertions:
          "When true, Mox-style `expect`/`expect_once` calls count (verified on exit).",
        treat_match_as_assertion:
          "When true, a refutable pattern match (`{:error, _} = call()`) counts: it raises on mismatch."
      ]
    ]

  alias OptimumCredo.TestsSupport

  @builtin [:catch_error, :catch_exit, :catch_throw, :flunk, :on_exit]
  @expectations [:expect, :expect_once]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    if TestsSupport.test_file?(source_file) do
      issue_meta = IssueMeta.for(source_file, params)

      config = %{
        helpers:
          params
          |> Params.get(:assertion_helpers, __MODULE__)
          |> Enum.map(&helper/1),
        bang?: Params.get(params, :treat_bang_call_as_assertion, __MODULE__),
        mocks?: Params.get(params, :treat_mock_expectations_as_assertions, __MODULE__),
        match?: Params.get(params, :treat_match_as_assertion, __MODULE__)
      }

      source_file
      |> TestsSupport.ast()
      |> TestsSupport.blocks([:test])
      |> Enum.reject(&(asserts?(&1, config) or helper_only?(&1, config.helpers)))
      |> Enum.map(fn test ->
        format_issue(issue_meta,
          message: "Test #{inspect(TestsSupport.name_text(test.name))} has no assertion.",
          line_no: test.line
        )
      end)
    else
      []
    end
  end

  defp asserts?(test, config) do
    TestsSupport.walk_env(
      test.body,
      false,
      fn node, env, acc ->
        acc =
          acc or
            node
            |> match_or_call(env)
            |> assertion?(config)

        {:cont, acc}
      end,
      test.env
    )
  end

  defp match_or_call({:=, _meta, [_pattern, _rhs]} = node, _env), do: node
  defp match_or_call(node, env), do: TestsSupport.call(node, env)

  defp assertion?({:=, _meta, [pattern, _rhs]}, config), do: config.match? and refutable?(pattern)
  defp assertion?(nil, _config), do: false

  defp assertion?(call, config) do
    string = Atom.to_string(call.fun)

    Regex.match?(~r/^(assert|refute)(_|$)/, string) or call.fun in @builtin or
      (call.fun == :verify! and call.module in [nil, "Mox"]) or
      (config.mocks? and call.fun in @expectations and length(call.args) >= 2) or
      (config.bang? and Regex.match?(~r/^[a-z_]\w*!$/u, string))
  end

  # A bare variable (or `_`) always matches; anything structural can raise `MatchError`.
  defp refutable?({name, _meta, context}) when is_atom(name) and is_atom(context), do: false
  defp refutable?({:=, _meta, [left, right]}), do: refutable?(left) or refutable?(right)
  defp refutable?(_pattern), do: true

  defp helper_only?(test, helpers) do
    case TestsSupport.statements(test.body) do
      [statement] ->
        call =
          statement
          |> pipeline_end()
          |> TestsSupport.call(test.env)

        call != nil and Enum.any?(helpers, &helper_call?(&1, call))

      _other ->
        false
    end
  end

  defp pipeline_end({:|>, _meta, [_left, right]}), do: pipeline_end(right)
  defp pipeline_end(statement), do: statement

  # A helper is a module name (or nil for any module) and a function name, both strings.
  defp helper({nil, fun}) when is_atom(fun), do: {nil, Atom.to_string(fun)}

  defp helper({module, fun}) when is_atom(fun),
    do: {TestsSupport.normalize_module(module), Atom.to_string(fun)}

  defp helper(name) do
    parts =
      name
      |> to_string()
      |> String.split(".")
      |> Enum.split(-1)

    case parts do
      {[], [fun]} -> {nil, fun}
      {modules, [fun]} -> {modules_name(modules), fun}
    end
  end

  defp modules_name(modules) do
    modules
    |> Enum.join(".")
    |> TestsSupport.normalize_module()
  end

  defp helper_call?({nil, fun}, call), do: Atom.to_string(call.fun) == fun

  defp helper_call?({module, fun}, call),
    do: Atom.to_string(call.fun) == fun and call.module == module
end
