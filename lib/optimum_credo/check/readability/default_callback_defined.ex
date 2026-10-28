defmodule OptimumCredo.Check.Readability.DefaultCallbackDefined do
  @moduledoc """
  Finds LiveView and LiveComponent callbacks that only repeat the framework default.

  Reported, inside modules that `use Phoenix.LiveView`, `use Phoenix.LiveComponent`, or
  `use MyAppWeb, :live_view` / `:live_component`:

  - a sole `mount/3` in a LiveView returning `{:ok, socket}` while ignoring its other arguments;
  - a sole `mount/1` in a LiveComponent returning `{:ok, socket}`;
  - a sole `update/2` in a LiveComponent equal to `{:ok, assign(socket, assigns)}`.

  Only single-clause, guard-free `def` definitions are reported, per module (nested modules are
  classified on their own); multi-clause callbacks may be deliberate. A bare
  `use SomeWeb, :html` module is not recognised as a LiveView, and an aliased
  `use LiveView` is not recognised either.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [],
    explanations: [
      check: """
      Do not define `mount/3`, `mount/1` or `update/2` when the body equals the default
      behaviour. Only single-clause, guard-free definitions with ignored arguments are
      reported. Opt-in, low priority.

      ## Bad

      ```elixir
      def mount(_params, _session, socket), do: {:ok, socket}
      ```

      ## Good

      Omit the callback.
      """
    ]

  alias OptimumCredo.OptimumIdiomsSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(
      source_file,
      fn
        {:defmodule, _meta, [_name, [do: body]]} = node, acc ->
          {node, acc ++ module_issues(body, issue_meta)}

        node, acc ->
          {node, acc}
      end
    )
  end

  defp module_issues(body, issue_meta) do
    statements = OptimumIdiomsSupport.statements(body)

    case OptimumIdiomsSupport.live_kind(statements) do
      nil ->
        []

      kind ->
        default_issues(statements, kind, issue_meta)
    end
  end

  defp default_issues(statements, kind, issue_meta) do
    clauses =
      for {:def, meta, [head, body]} <- statements, do: {clause_name(head), meta, head, body}

    counts = Enum.frequencies_by(clauses, fn {name, _element2, _element3, _element4} -> name end)

    for {name, meta, head, body} <- clauses,
        counts[name] == 1,
        default?(name, kind, head, body) do
      format_issue(issue_meta,
        message:
          "`#{elem(name, 0)}/#{elem(name, 1)}` only repeats the default; remove the callback.",
        line_no: meta[:line] || 1
      )
    end
  end

  defp clause_name({:when, _meta, [head | _tail]}), do: clause_name(head)

  defp clause_name({name, _meta, args}) when is_atom(name) and is_list(args),
    do: {name, length(args)}

  defp clause_name(_head), do: {nil, 0}

  defp default?({:mount, 3}, :view, {:mount, _meta, [params, session, socket]}, do: body),
    do: ignored?(params) and ignored?(session) and ok_socket?(body, socket)

  defp default?({:mount, 1}, :component, {:mount, _meta, [socket]}, do: body),
    do: ok_socket?(body, socket)

  defp default?({:update, 2}, :component, {:update, _meta, [assigns, socket]}, do: body),
    do: assign_all?(body, assigns, socket)

  defp default?(_name, _kind, _head, _body), do: false

  defp ignored?({name, _meta, context}) when is_atom(name) and is_atom(context) do
    name
    |> Atom.to_string()
    |> String.starts_with?("_")
  end

  defp ignored?(_pattern), do: false

  defp ok_socket?({:ok, {name, _meta, context}}, {name, _tuple_meta, context}) when is_atom(name),
    do: true

  defp ok_socket?(_body, _socket), do: false

  defp assign_all?(
         {:ok,
          {assign, _meta, [{socket, _tuple_meta, context}, {assigns, _ignored, assigns_context}]}},
         {assigns, _meta2, assigns_context},
         {socket, _meta3, context}
       )
       when is_atom(context) and is_atom(assigns_context),
       do: assign_call?(assign)

  defp assign_all?(_body, _assigns, _socket), do: false

  defp assign_call?(:assign), do: true

  defp assign_call?({:., _meta, [{:__aliases__, _alias_meta, [:Phoenix, :Component]}, :assign]}),
    do: true

  defp assign_call?(_call), do: false
end
