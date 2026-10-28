defmodule OptimumCredo.Check.Refactor.ToggleOnlyHandleEvent do
  @moduledoc """
  Hints at LiveView `handle_event/3` clauses that only flip a boolean assign which a single
  `:if` in the same module's `~H` template consumes.

  Such purely presentational toggles can usually run on the client with `Phoenix.LiveView.JS`
  and avoid a server round trip.

  Recognised handler bodies are exactly `{:noreply, assign(socket, :key, !socket.assigns.key)}`
  (also `not`, `socket.assigns[:key]`, and the piped form) and
  `{:noreply, update(socket, :key, &(!&1))}` / `fn v -> not v end`. The handler is reported only
  when the module has inline `~H` templates, `@key` occurs in them exactly once as
  `:if={@key}` on a tag or `<%= if @key do %>`, and no other code in the module reads the
  assign. Only the module's own `~H` sigils count (not a nested module's or a sibling
  module's in the same file), the handler must update and read its own socket variable, and
  mentions inside HTML or HEEx comments and `<script>`/`<style>` bodies are not seen.
  Templates in separate files cannot be inspected, so those modules are not reported unless
  `require_inline_template` is `false`. Reads through pattern matching on `socket.assigns`
  elsewhere are not tracked.

  ## Parameters

  - `require_inline_template`: only report when an inline template proves the single `:if`
    consumer (default `true`).
  """

  use Credo.Check,
    base_priority: :low,
    category: :refactor,
    param_defaults: [require_inline_template: true],
    explanations: [
      check: """
      A handler that only toggles a boolean read by one `:if` can use `JS.toggle/1` or
      `JS.show/hide` instead of a server round trip. Reported only for recognisable
      toggle-only handlers in modules whose inline template has a single `:if` consumer.
      Suggestion-grade; opt-in, low priority.
      """,
      params: [
        require_inline_template:
          "Require an inline `~H` template proving the single consumer; set to false to report without it."
      ]
    ]

  alias OptimumCredo.OptimumIdiomsSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    require_template = Params.get(params, :require_inline_template, __MODULE__)

    if OptimumIdiomsSupport.heex_file?(source_file) do
      []
    else
      Credo.Code.prewalk(source_file, fn
        {:defmodule, _meta, [_name, [do: body]]} = node, acc ->
          {node, acc ++ module_issues(body, require_template, issue_meta)}

        node, acc ->
          {node, acc}
      end)
    end
  end

  # Only this module's own code and templates count; nested modules are judged separately.
  defp module_issues(body, require_template, issue_meta) do
    own = OptimumIdiomsSupport.without_nested_modules(body)
    statements = OptimumIdiomsSupport.statements(own)

    if OptimumIdiomsSupport.live_kind(statements) do
      toggle_issues(own, statements, require_template, issue_meta)
    else
      []
    end
  end

  defp toggle_issues(own, statements, require_template, issue_meta) do
    toggles = for statement <- statements, toggle = toggle(statement), do: toggle

    fragments =
      own
      |> OptimumIdiomsSupport.heex_visible_text_in()
      |> Enum.map(&elem(&1, 0))

    tags = tags_in(own)

    for {key, meta, handler} <- toggles,
        single_consumer?(key, fragments, tags, require_template),
        reads(own, key) == reads(handler, key) do
      format_issue(issue_meta,
        message:
          "This handler only toggles `:#{key}`; consider `Phoenix.LiveView.JS` to avoid the round trip.",
        line_no: meta[:line] || 1
      )
    end
  end

  defp toggle({:def, meta, [head, [do: body]]} = handler) do
    head =
      case head,
        do: (
          {:when, _meta, [head | _tail]} -> head
          head -> head
        )

    with {:handle_event, _meta, [event, _params, socket]} when is_binary(event) <- head,
         {:noreply, call} <- OptimumIdiomsSupport.unpipe(body),
         key when is_atom(key) <- toggled_key(call),
         true <- on_socket?(call, socket) do
      {key, meta, handler}
    else
      _other -> nil
    end
  end

  defp toggle(_statement), do: nil

  # The handler's own socket variable must be the one updated and read.
  defp on_socket?(
         {_assign_or_update, _meta, [{name, _tuple_meta, context} | _tail]},
         {name, _ignored, context}
       ),
       do: is_atom(name) and is_atom(context)

  defp on_socket?(_call, _socket), do: false

  defp toggled_key({:assign, _meta, [_socket, key, {negation, _tuple_meta, [read]}]})
       when is_atom(key) and negation in [:!, :not],
       do: if(assign_read?(read, key), do: key)

  defp toggled_key({:update, _meta, [_socket, key, function]}) when is_atom(key),
    do: if(negating_function?(function), do: key)

  defp toggled_key(_call), do: nil

  defp assign_read?(
         {{:., _meta, [{{:., _dot_meta, [_socket, :assigns]}, _tuple_meta, []}, key]}, _ignored,
          []},
         key
       ),
       do: true

  defp assign_read?(
         {{:., _meta, [Access, :get]}, _tuple_meta,
          [{{:., _dot_meta, [_socket, :assigns]}, _ignored, []}, key]},
         key
       ),
       do: true

  defp assign_read?(_read, _key), do: false

  defp negating_function?({:&, meta, [{:__block__, _meta, [inner]}]}),
    do: negating_function?({:&, meta, [inner]})

  defp negating_function?({:&, _meta, [{negation, _tuple_meta, [{:&, _meta2, [1]}]}]})
       when negation in [:!, :not],
       do: true

  defp negating_function?(
         {:fn, _meta,
          [
            {:->, _arrow_meta,
             [[{name, _tuple_meta, ctx}], {negation, _ignored, [{name, _meta2, ctx}]}]}
          ]}
       )
       when negation in [:!, :not],
       do: true

  defp negating_function?(_function), do: false

  defp single_consumer?(_key, [], _tags, require_template), do: not require_template

  defp single_consumer?(key, fragments, tags, _require_template) do
    text = Enum.join(fragments, "\n")

    name =
      key
      |> Atom.to_string()
      |> Regex.escape()

    references = Regex.scan(~r/@#{name}(?![\w?!])/, text)
    eex_consumers = Regex.scan(~r/<%=?\s*if\s+@#{name}\s+do/, text)
    attribute_consumers = Enum.count(tags, &if_attribute?(&1, key))

    length(references) == 1 and length(eex_consumers) + attribute_consumers == 1
  end

  # `:if={@key}` on a real tag; text or comments that merely mention it do not count.
  defp tags_in(ast) do
    ast
    |> OptimumIdiomsSupport.heex_tags_in()
    |> Enum.flat_map(& &1.attrs)
  end

  defp if_attribute?({":if", {:expr, expression}, _line}, key),
    do: String.trim(expression) == "@" <> Atom.to_string(key)

  defp if_attribute?(_attribute, _key), do: false

  # Number of places that read the assign from `socket.assigns`, `assigns[:key]` or `assigns.key`.
  defp reads(ast, key) do
    ast
    |> Macro.prewalk(0, fn
      {{:., _meta, [{{:., _dot_meta, [_socket, :assigns]}, _tuple_meta, []}, ^key]}, _ignored, []} =
          node,
      count ->
        {node, count + 1}

      {{:., _meta, [Access, :get]}, _tuple_meta,
       [{{:., _dot_meta, [_socket, :assigns]}, _ignored, []}, ^key]} = node,
      count ->
        {node, count + 1}

      {{:., _meta, [{:assigns, _assigns_meta, _args}, ^key]}, _tuple_meta, []} = node, count ->
        {node, count + 1}

      node, count ->
        {node, count}
    end)
    |> elem(1)
  end
end
