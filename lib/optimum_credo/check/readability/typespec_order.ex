defmodule OptimumCredo.Check.Readability.TypespecOrder do
  @moduledoc """
  A check that ensures typespecs are alphabetically ordered.

  Alphabetically ordered typespecs are more easily scannable by the reader.
  This check enforces that typespecs (@type, @typep, @opaque) are ordered alphabetically within their groups.
  """

  use Credo.Check,
    id: "EX9002",
    base_priority: :low,
    param_defaults: [
      sort_method: :alpha
    ],
    explanations: [
      check: """
      Alphabetically ordered typespecs are more easily scannable by the reader.

          # preferred

          @type apple :: String.t()
          @type banana :: String.t()
          @type cherry :: String.t()

          # NOT preferred

          @type apple :: String.t()
          @type cherry :: String.t()
          @type banana :: String.t()

      Typespecs should be alphabetically ordered among their group:

          # preferred

          @type apple :: String.t()
          @type banana :: String.t()

          @typep color :: String.t()
          @typep dimension :: integer()

          # NOT preferred

          @type banana :: String.t()
          @type apple :: String.t()

          @typep dimension :: integer()
          @typep color :: String.t()

      Like all `Readability` issues, this one is not a technical concern.
      But you can improve the odds of others reading and liking your code by making
      it easier to follow.
      """,
      params: [
        sort_method: """
        The ordering method to use.

        Options
        - `:alpha` - Alphabetical case-insensitive sorting.
        - `:ascii` - Case-sensitive sorting where upper case characters are ordered
                      before their lower case equivalent.
        """
      ]
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    sort_method = Params.get(params, :sort_method, __MODULE__)
    issue_meta = IssueMeta.for(source_file, params)

    tokens = Credo.Code.to_tokens(source_file)

    type_definitions = collect_type_definitions(tokens)

    type_groups = group_type_definitions(type_definitions)

    check_ordering_in_groups(type_groups, sort_method, issue_meta)
  end

  defp collect_type_definitions(tokens) do
    tokens
    |> Enum.reduce({1, [], []}, fn
      {:eol, {line, _col1, _meta1}, _value}, {_curr_line, curr_line_tokens, lines} ->
        {line + 1, [], [Enum.reverse(curr_line_tokens) | lines]}

      token = {_type, {line, _col2, _meta2}, _value}, {curr_line, curr_line_tokens, lines} ->
        if line == curr_line do
          {curr_line, [token | curr_line_tokens], lines}
        else
          {line, [token],
           if(curr_line_tokens == [], do: lines, else: [Enum.reverse(curr_line_tokens) | lines])}
        end

      token, {curr_line, curr_line_tokens, lines} ->
        {curr_line, [token | curr_line_tokens], lines}
    end)
    |> then(fn {_curr_line, last_line, lines} ->
      if last_line == [], do: lines, else: [Enum.reverse(last_line) | lines]
    end)
    |> Enum.reverse()
    |> Enum.flat_map(fn line_tokens -> extract_types_from_line(line_tokens) end)
  end

  defp extract_types_from_line(line_tokens) do
    case line_tokens do
      [
        {:at_op, {line, _col1, _meta1}, :@},
        {:identifier, {line, _col2, _meta2}, kind},
        {:identifier, {line, _col3, _meta3}, name} | _rest
      ]
      when kind in [:type, :typep, :opaque] ->
        [{kind, line, name}]

      _other ->
        []
    end
  end

  defp group_type_definitions(definitions) do
    definitions
    |> Enum.sort_by(fn {_kind, line, _name} -> line end)
    |> Enum.reduce([], fn
      def = {_kind, _line, _name}, [] ->
        [[def]]

      def = {kind, line, _name},
      [[{prev_kind, prev_line, _prev_name} | _rest] = group | groups] ->
        if line > prev_line + 1 || kind != prev_kind do
          [[def] | [group | groups]]
        else
          [[def | group] | groups]
        end
    end)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
  end

  defp check_ordering_in_groups(groups, sort_method, issue_meta) do
    Enum.flat_map(groups, &check_group_order(&1, sort_method, issue_meta))
  end

  defp check_group_order(group, sort_method, issue_meta) do
    group
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [{kind1, line1, name1}, {_kind2, _line2, name2}] ->
      if out_of_order?(name1, name2, sort_method) do
        [issue_for(issue_meta, line1, kind1, name1)]
      else
        []
      end
    end)
  end

  defp out_of_order?(name1, name2, :alpha) do
    name1 = to_string(name1)
    name2 = to_string(name2)
    String.downcase(name1) > String.downcase(name2)
  end

  defp out_of_order?(name1, name2, :ascii) do
    name1 = to_string(name1)
    name2 = to_string(name2)
    name1 > name2
  end

  defp issue_for(issue_meta, line_no, kind, type_name) do
    format_issue(
      issue_meta,
      message:
        "The typespec `@#{kind} #{type_name}` is not alphabetically ordered among its group.",
      trigger: type_name,
      line_no: line_no
    )
  end
end
