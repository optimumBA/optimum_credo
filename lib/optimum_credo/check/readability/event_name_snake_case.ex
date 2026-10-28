defmodule OptimumCredo.Check.Readability.EventNameSnakeCase do
  @moduledoc """
  Finds LiveView event names that contain a dash or an uppercase letter.

  Reported: string literals in `handle_event("some-name", _, _)` heads (arity 3, also as
  `"some-name" = event`), `push_event(socket, "some-name", ...)`, and quoted event attributes
  (`phx-click`, `phx-submit`, `phx-change`, `phx-blur`, `phx-focus`, `phx-keydown`, `phx-keyup`,
  `phx-click-away`, `phx-capture-click`, `phx-viewport-top/bottom`, `phx-window-*`) inside `~H`
  sigils. A raw `.heex` source file is scanned only when handed to the check directly; stock
  `mix credo` parses every file as Elixir and drops `.heex` files as invalid, so in a normal run
  only `~H` sigils are inspected.

  Event names built dynamically, and attribute values that are expressions
  (`phx-click={...}`), cannot be checked. Attributes inside HTML or HEEx comments and
  `<script>`/`<style>` bodies are ignored. Phoenix-internal names that start with `lv:` are
  ignored. Names are only compared by spelling; `JS.push/2` is not inspected.

  ## Parameters

  - `allowed_events`: event names to accept as written, such as JS-hook contracts.
  - `check_heex`: whether to inspect `phx-*` attributes in templates (default `true`).
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [allowed_events: [], check_heex: true],
    explanations: [
      check: """
      Event names use `snake_case`, ideally `<verb>_<noun>`. Dashes and uppercase letters
      are reported in `handle_event/3` heads, `push_event/3` calls, and `phx-*` string
      attributes in `~H` templates. Dynamic names are not inspected. Opt-in, low priority.

      ## Bad

      ```elixir
      def handle_event("save-draft", _params, socket), do: {:noreply, socket}
      ```

      ## Good

      ```elixir
      def handle_event("save_draft", _params, socket), do: {:noreply, socket}
      ```
      """,
      params: [
        allowed_events: "Event names accepted as written.",
        check_heex:
          "Also inspect `phx-*` attributes in `~H` sigils (and raw `.heex` sources passed directly)."
      ]
    ]

  alias OptimumCredo.OptimumIdiomsSupport

  @event_attribute ~r/\Aphx-(?:click|submit|change|blur|focus|keydown|keyup|capture-click|click-away|viewport-top|viewport-bottom|window-[a-z]+)\z/i

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    allowed =
      params
      |> Params.get(:allowed_events, __MODULE__)
      |> Enum.map(&to_string/1)

    check_heex = Params.get(params, :check_heex, __MODULE__)

    for {name, line, where} <- event_hits(source_file, check_heex),
        bad_name?(name),
        name not in allowed do
      format_issue(issue_meta,
        message: "Event name #{inspect(name)} (#{where}) should be snake_case.",
        line_no: line
      )
    end
  end

  defp event_hits(source_file, check_heex) do
    elixir_hits =
      if OptimumIdiomsSupport.heex_file?(source_file), do: [], else: elixir_events(source_file)

    elixir_hits ++ if(check_heex, do: heex_events(source_file), else: [])
  end

  defp heex_events(source_file) do
    for tag <- OptimumIdiomsSupport.heex_tags(source_file),
        {attribute, {:string, name}, line} <- tag.attrs,
        Regex.match?(@event_attribute, attribute),
        do: {name, line, "#{attribute} attribute"}
  end

  defp bad_name?("lv:" <> _ignored), do: false
  defp bad_name?(name), do: String.contains?(name, "-") or name != String.downcase(name)

  defp elixir_events(source_file) do
    ast = Credo.SourceFile.ast(source_file)
    head_hits(ast) ++ push_event_hits(ast)
  end

  defp head_hits(ast) do
    ast
    |> Macro.prewalk([], fn
      {kind, _meta, [{:when, _when_meta, [head | _tail]}, _body]} = node, acc
      when kind in [:def, :defp] ->
        {node, collect_head(head, acc)}

      {kind, _meta, [head, _body]} = node, acc when kind in [:def, :defp] ->
        {node, collect_head(head, acc)}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp push_event_hits(ast) do
    ast
    |> OptimumIdiomsSupport.without_definition_heads()
    |> OptimumIdiomsSupport.unpipe()
    |> Macro.prewalk([], fn
      {call, meta, [_socket, name | _tail]} = node, acc when is_binary(name) and is_list(meta) ->
        if push_event?(call),
          do: {node, [{name, meta[:line] || 1, "push_event"} | acc]},
          else: {node, acc}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp collect_head({:handle_event, meta, [name, _params, _socket]}, acc) do
    case literal_event(name) do
      nil -> acc
      event -> [{event, meta[:line] || 1, "handle_event"} | acc]
    end
  end

  defp collect_head(_head, acc), do: acc

  # `"save-draft"`, or either side of `"save-draft" = event` / `event = "save-draft"`.
  defp literal_event(name) when is_binary(name), do: name

  defp literal_event({:=, _meta, [left, right]}),
    do: literal_event(left) || literal_event(right)

  defp literal_event(_pattern), do: nil

  defp push_event?(:push_event), do: true
  defp push_event?({:., _meta, [_module, :push_event]}), do: true
  defp push_event?(_call), do: false
end
