defmodule OptimumCredo.Check.Readability.SpecWithImpl do
  @moduledoc """
  Finds `@spec` declarations attached to a function that also carries `@impl`.

  A callback implementation inherits its contract from the behaviour, so the
  `@spec` is redundant. The check reads each module (or `defimpl`) body in source
  order: a `@spec` for a function name is reported when an `@impl` other than
  `@impl false` is pending for the same definition, in either attribute order.

  A `@spec` that deliberately narrows the callback's type (for example an Oban worker's
  `perform/1` listing only the results it can return) is reported as well, because the
  check cannot read the behaviour's callback type; keep such specs by not enabling the
  check for those modules or by adopting the convention project-wide.

  This is a static heuristic. Specs are matched to definitions by function name and
  arity (default arguments cover the lower arities), so a `@spec` for a helper of another
  arity next to a callback is left alone. An `@impl` that applies to a later clause of an
  already-defined function is not followed, and `@impl` set inside macros or `quote`
  blocks is not inspected.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    explanations: [
      check: """
      A function annotated with `@impl` implements a callback, whose spec is already
      defined by the behaviour. Remove the `@spec`.

      ## Bad

      ```elixir
      @impl Phoenix.LiveView
      @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
      def mount(params, session, socket), do: {:ok, socket}
      ```

      ## Good

      ```elixir
      @impl Phoenix.LiveView
      def mount(params, session, socket), do: {:ok, socket}
      ```

      `@impl false` is not treated as a callback. Specs are matched by function name.
      """
    ]

  alias OptimumCredo.OptimumStructureSupport

  @def_kinds [:def, :defp, :defmacro, :defmacrop, :defdelegate]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, issue_meta))
    |> Enum.reverse()
  end

  defp traverse({kind, _meta, [_name, [do: body]]} = ast, issues, issue_meta)
       when kind in [:defmodule, :defimpl] do
    {ast, scan(OptimumStructureSupport.statements(body), issue_meta, issues)}
  end

  defp traverse({:defimpl, _meta, [_name, _opts, [do: body]]} = ast, issues, issue_meta) do
    {ast, scan(OptimumStructureSupport.statements(body), issue_meta, issues)}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp scan(statements, issue_meta, issues) do
    {issues, _impl?, _specs} =
      Enum.reduce(statements, {issues, false, []}, &fold(&1, &2, issue_meta))

    issues
  end

  defp fold({:@, _meta, [{:impl, _impl_meta, [value]}]}, {issues, _impl?, specs}, _issue_meta) do
    {issues, value != false, specs}
  end

  defp fold({:@, meta, [{:spec, _meta, [spec]}]}, {issues, impl?, specs}, _issue_meta) do
    {issues, impl?, [{spec_name(spec), spec_arity(spec), meta[:line] || 1} | specs]}
  end

  defp fold({kind, _meta, [head | _rest]}, {issues, impl?, specs}, issue_meta)
       when kind in @def_kinds do
    name = OptimumStructureSupport.head_name(head)
    args = OptimumStructureSupport.head_args(head)
    defaults = Enum.count(args, &match?({:\\, _meta, _args}, &1))
    arities = (length(args) - defaults)..length(args)//1

    {impl_spec_issues(impl?, specs, {name, arities}, issue_meta, issues), false, []}
  end

  defp fold(_other, state, _issue_meta), do: state

  defp impl_spec_issues(true, specs, {name, arities}, issue_meta, issues) do
    specs
    |> Enum.filter(fn {spec_name, arity, _line} -> spec_name == name and arity in arities end)
    |> Enum.reduce(issues, fn {_name, _arity, line}, acc ->
      [issue(issue_meta, name, line) | acc]
    end)
  end

  defp impl_spec_issues(false, _specs, _head, _issue_meta, issues), do: issues

  defp spec_name({:when, _meta, [spec | _constraints]}), do: spec_name(spec)

  defp spec_name({:"::", _meta, [{name, _tuple_meta, _args}, _return]}) when is_atom(name),
    do: name

  defp spec_name(_spec), do: nil

  defp spec_arity({:when, _meta, [spec | _constraints]}), do: spec_arity(spec)

  defp spec_arity({:"::", _meta, [{_name, _tuple_meta, args}, _return]}) when is_list(args),
    do: length(args)

  defp spec_arity(_spec), do: nil

  defp issue(issue_meta, name, line) do
    format_issue(issue_meta,
      message: "Remove @spec for #{name}; the @impl callback already defines its contract.",
      line_no: line
    )
  end
end
