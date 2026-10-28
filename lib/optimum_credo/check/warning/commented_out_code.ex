defmodule OptimumCredo.Check.Warning.CommentedOutCode do
  @moduledoc """
  Finds runs of own-line comments whose text parses as Elixir code.

  Comments come from the tokenizer, so string and heredoc contents (`@doc`) are never
  considered. A run is any block of adjacent own-line comment lines (blank `#` lines
  included, indentation of the `#` ignored). It is reported when at least `min_lines` of its
  lines are individually code-like, or when the whole run parses as code (a trailing `end`
  is supplied for commented-out blocks, and a leading `|>` line gets a dummy receiver).

  Code-like means: a call with parentheses, a `do` block, a pipe (also a line that starts
  with `|>`), a match whose right side is such code, a definition or DSL macro call with a
  literal argument (`def f, do: 1`, `field :name, :string`, `alias A.B`, `@attr "x"`), or a
  qualified module entry such as `My.Cache,`. Bare words and atoms (`# done`, `# :ok`) never
  count. A lone line is reported only when it unmistakably is code: it ends with `do`/`->`,
  is a qualified module entry ending in a comma, or is a debug call (`IO.inspect(..)`,
  `dbg(..)`); use `min_lines: 1` to report every code-like line.

  Skipped: lines starting with `ignore_prefixes`, `credo:`, `sobelow_skip`, `iex>`/`...>`
  and `#!`, and runs where prose ending in `:` (`e.g.`, `Example`, or the generated router's "Other scopes may use custom stacks.") precedes the first
  code line (an example in documentation, as in generated `config/runtime.exs`), unless that
  prose says the code is disabled, old, removed or to be uncommented. Static limits: prose that happens to look like a
  call, and code fragments that do not parse on their own, are misjudged.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [min_lines: 2, ignore_prefixes: ["TODO:", "FIXME:", "NOTE:"]],
    explanations: [
      check: """
      Delete commented-out code; version control remembers it. Use `# TODO:`/`# FIXME:` for
      real follow-ups.

      Bad:

          # IO.inspect(socket.assigns)
          # Repo.delete_all(User)

      Good: remove the lines.
      """,
      params: [
        min_lines: "Code-like lines required in a run (a single `... do` line always counts).",
        ignore_prefixes: "Comment text prefixes that are never treated as code."
      ]
    ]

  alias OptimumCredo.TestsSupport

  @pragmas ["credo:", "sobelow_skip", "iex>", "...>", "!"]

  @dsl_names ~w(def defp defmacro defmacrop defdelegate defguard defstruct defexception defimpl
                defprotocol alias import require use field belongs_to has_many has_one many_to_many
                embeds_one embeds_many plug pipe_through scope get post put patch delete forward live
                resources attr slot on_mount config import_config)a

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    min = Params.get(params, :min_lines, __MODULE__)
    prefixes = ignored_prefixes(params)

    source_file
    |> TestsSupport.comments()
    |> Enum.filter(&reportable_comment?(&1, prefixes))
    |> runs()
    |> Enum.map(&trim_blank/1)
    |> Enum.filter(&(&1 != [] and not example_run?(&1) and code_run?(&1, min)))
    |> Enum.map(&run_issue(&1, issue_meta))
  end

  defp run_issue([first | _tail], issue_meta) do
    format_issue(issue_meta,
      message: "Commented-out code; delete it instead (version control keeps history).",
      line_no: first.line
    )
  end

  defp ignored_prefixes(params), do: Params.get(params, :ignore_prefixes, __MODULE__) ++ @pragmas

  defp reportable_comment?(comment, prefixes) do
    comment.own_line? and not Enum.any?(prefixes, &String.starts_with?(comment.text, &1))
  end

  defp runs(comments) do
    Enum.chunk_while(
      comments,
      [],
      fn
        c, [] ->
          {:cont, [c]}

        c, [prev | _tail] = run ->
          if c.line == prev.line + 1,
            do: {:cont, [c | run]},
            else: {:cont, Enum.reverse(run), [c]}
      end,
      fn
        [] -> {:cont, []}
        run -> {:cont, Enum.reverse(run), []}
      end
    )
  end

  defp trim_blank(run) do
    run
    |> Enum.drop_while(&(&1.text == ""))
    |> Enum.reverse()
    |> Enum.drop_while(&(&1.text == ""))
    |> Enum.reverse()
  end

  # Prose that introduces an example ("... to your configuration:", "e.g.") followed by code
  # documents something; a lead-in that says the code is disabled/old does not.
  @disabled_words ~r/\b(disabled|commented|comment out|uncomment|temporar|until|old|legacy|deprecated|no longer|removed?)\b/i

  defp example_run?(run) do
    {lead_in, rest} = Enum.split_while(run, &(not code_like?(&1.text)))

    lead_in != [] and rest != [] and
      Enum.any?(lead_in, &introduces_example?/1) and
      not Enum.any?(lead_in, &Regex.match?(@disabled_words, &1.text))
  end

  defp introduces_example?(%{text: text}) do
    String.ends_with?(text, ":") or
      Regex.match?(~r/^(e\.g\.|for example|example|usage)\b/i, text) or
      Regex.match?(~r/^other scopes may use custom stacks\.?$/i, text)
  end

  defp code_run?(run, min) do
    texts = Enum.map(run, & &1.text)
    individual = Enum.count(texts, &code_like?/1)

    individual >= min or (length(run) >= min and whole_run_code?(texts)) or
      (length(run) == 1 and
         texts
         |> hd()
         |> strong_single?())
  end

  defp whole_run_code?(texts) do
    joined = Enum.join(texts, "\n")
    prefix = if String.starts_with?(joined, "|>"), do: "x\n", else: ""
    Enum.any?([joined, joined <> "\nend"], &code_ast?(prefix <> &1))
  end

  defp strong_single?(text) do
    cond do
      Regex.match?(~r/^[A-Z]\w*(\.[A-Z]\w*)+,$/, text) -> true
      Regex.match?(~r/(^|\|>\s*)(IO\.inspect|IO\.puts|dbg)\b/, text) -> code_like?(text)
      String.ends_with?(text, " do") or String.ends_with?(text, "->") -> code_like?(text)
      true -> false
    end
  end

  defp code_like?(text) do
    text = String.trim_trailing(text, ",")

    cond do
      Regex.match?(~r/^[A-Z]\w*(\.[A-Z]\w*)+$/, text) -> true
      String.ends_with?(text, " do") -> code_ast?(text <> "\nend")
      String.ends_with?(text, "->") -> code_ast?(text <> " nil end)")
      String.starts_with?(text, "|>") -> code_ast?("x " <> text)
      true -> code_ast?(text)
    end
  end

  defp code_ast?(text) do
    case Code.string_to_quoted(text, token_metadata: true, emit_warnings: false) do
      {:ok, ast} -> code_node?(ast)
      _other -> false
    end
  end

  defp code_node?({:__block__, _meta, nodes}), do: Enum.any?(nodes, &code_node?/1)
  defp code_node?({:|>, _meta, _args}), do: true
  defp code_node?({:=, _meta, [_lhs, rhs]}), do: code_node?(rhs)

  defp code_node?({:@, _meta, [{_attribute, _tuple_meta, [value]}]}), do: literal_shape?(value)

  defp code_node?({{:., _meta, _args}, meta, args}) when is_list(args),
    do: meta[:closing] != nil or meta[:do] != nil

  # Tuples, maps and structs also carry `closing` metadata but are data, not calls.
  defp code_node?({name, _meta, args})
       when name in [:{}, :%{}, :%, :<<>>, :__aliases__] and is_list(args),
       do: false

  defp code_node?({name, meta, args}) when is_atom(name) and is_list(args) do
    meta[:closing] != nil or meta[:do] != nil or
      (name in @dsl_names and Enum.any?(args, &literal_shape?/1))
  end

  defp code_node?(_other), do: false

  # An argument that is clearly code rather than a bare word of prose.
  defp literal_shape?(arg) when is_atom(arg) or is_binary(arg) or is_number(arg), do: true
  defp literal_shape?(arg) when is_list(arg), do: true
  defp literal_shape?({_left, _right}), do: true
  defp literal_shape?({:__aliases__, _meta, _args}), do: true
  defp literal_shape?({kind, _meta, _args}) when kind in [:{}, :%{}, :%, :fn, :&, :<<>>], do: true
  defp literal_shape?({_name, meta, args}) when is_list(args), do: meta[:closing] != nil
  defp literal_shape?(_other), do: false
end
