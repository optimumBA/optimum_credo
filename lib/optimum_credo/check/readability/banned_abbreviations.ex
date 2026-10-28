defmodule OptimumCredo.Check.Readability.BannedAbbreviations do
  @moduledoc """
  Finds function, variable, and attribute names that contain a banned abbreviation.

  Names are split on `_` and each segment is compared with `banned_abbreviations`, so
  `msg`, `_msg`, `user_msg`, and `valid_msg?` are all reported for `msg`. Names are
  inspected where they are introduced: `def`/`defp` names and parameters, variables on
  the left of `=` and `<-`, `fn` and `case`/`receive`/`with` clause patterns, and module
  attribute definitions. Pinned variables, `cond` conditions, atoms, strings, map keys,
  and uses of an existing variable are not reported.

  This is a conservative, opt-in naming heuristic. The default list is deliberately
  short; abbreviations that are idiomatic in Elixir (`ctx`, `opts`, `acc`, `ref`)
  are not included. Whether a name is clear is ultimately a human judgement.

  ## Parameters

  - `banned_abbreviations`: a keyword list or map of `abbreviation: suggestion`
    (the suggestion may be `nil`), or a plain list of abbreviations. Replaces the
    default list.
  - `allowed_names`: complete names (atoms or strings) that are accepted anyway.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [
      banned_abbreviations: [
        acct: "account",
        btn: "button",
        cfg: "config",
        cust: "customer",
        idx: "index",
        mgr: "manager",
        msg: "message",
        pwd: "password",
        qty: "quantity",
        tmp: "temporary",
        usr: "user"
      ],
      allowed_names: []
    ],
    explanations: [
      check: """
      Prefer complete words over abbreviations, using the business-domain term.

      ## Bad

      ```elixir
      def send_msg(usr, cfg), do: deliver(usr, cfg)
      ```

      ## Good

      ```elixir
      def send_message(user, config), do: deliver(user, config)
      ```

      Names are split on `_` and checked where they are introduced. The default list
      is short; configure `banned_abbreviations` for your domain.
      """,
      params: [
        banned_abbreviations: "Abbreviations to report, optionally with a suggestion.",
        allowed_names: "Complete names that are accepted."
      ]
    ]

  alias OptimumCredo.OptimumStructureSupport

  @def_kinds [:def, :defp, :defmacro, :defmacrop, :defdelegate]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    banned =
      params
      |> Params.get(:banned_abbreviations, __MODULE__)
      |> normalize()

    allowed =
      params
      |> Params.get(:allowed_names, __MODULE__)
      |> OptimumStructureSupport.to_strings()

    source_file
    |> Credo.SourceFile.ast()
    |> introduced()
    |> Enum.uniq()
    |> Enum.flat_map(fn {name, line} ->
      string = Atom.to_string(name)

      with false <- string in allowed,
           {abbreviation, suggestion} <- find_abbreviation(string, banned) do
        [
          format_issue(issue_meta,
            message: "Avoid the abbreviation #{abbreviation} in #{string}#{suggest(suggestion)}.",
            line_no: line
          )
        ]
      else
        _other -> []
      end
    end)
  end

  defp normalize(banned) when is_map(banned) do
    banned
    |> Map.to_list()
    |> normalize()
  end

  defp normalize(banned) when is_list(banned) do
    Map.new(banned, fn
      {abbreviation, suggestion} -> {to_string(abbreviation), suggestion}
      abbreviation -> {to_string(abbreviation), nil}
    end)
  end

  defp normalize(banned) do
    raise ArgumentError,
          "invalid banned_abbreviations #{inspect(banned)} for #{inspect(__MODULE__)}; " <>
            "use a keyword list, map, or list of abbreviations"
  end

  defp find_abbreviation(name, banned) do
    name
    |> String.trim_leading("_")
    |> String.trim_trailing("?")
    |> String.trim_trailing("!")
    |> String.split("_", trim: true)
    |> Enum.find_value(fn segment ->
      if Map.has_key?(banned, segment), do: {segment, Map.fetch!(banned, segment)}
    end)
  end

  defp suggest(nil), do: ""
  defp suggest(suggestion), do: "; use #{suggestion}"

  # Collects {name, line} for every name introduced in the AST.
  defp introduced({kind, meta, [head | _rest] = args}) when kind in @def_kinds do
    name = OptimumStructureSupport.head_name(head)
    own = if name, do: [{name, meta[:line] || 1}], else: []

    head_vars =
      head
      |> OptimumStructureSupport.head_args()
      |> pattern_vars()

    own ++ head_vars ++ introduced_in(args)
  end

  defp introduced({:cond, _meta, [[do: clauses]]}) when is_list(clauses) do
    Enum.flat_map(clauses, fn
      {:->, _meta, [_condition, body]} -> introduced(body)
      other -> introduced(other)
    end)
  end

  defp introduced({:@, meta, [{name, _meta, [value]}]}) when is_atom(name),
    do: [{name, meta[:line] || 1} | introduced(value)]

  defp introduced({operator, _meta, [left, right]}) when operator in [:=, :<-] do
    pattern_vars(left) ++ introduced(left) ++ introduced(right)
  end

  defp introduced({:->, _meta, [params, body]}) when is_list(params),
    do: pattern_vars(params) ++ introduced(body)

  defp introduced(term) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> introduced_in()
  end

  defp introduced(list) when is_list(list), do: introduced_in(list)
  defp introduced(_term), do: []

  defp introduced_in(terms), do: Enum.flat_map(terms, &introduced/1)

  # A guard follows the patterns: `fn a, b when is_atom(a) -> ... end` holds `[a, b, guard]`.
  defp pattern_vars({:when, _meta, [_head | _tail] = patterns}) do
    patterns
    |> Enum.drop(-1)
    |> pattern_vars()
  end

  defp pattern_vars({:^, _meta, _args}), do: []

  defp pattern_vars({name, meta, context}) when is_atom(name) and is_atom(context) do
    if dunder?(name) or name == :_ do
      []
    else
      [{name, meta[:line] || 1}]
    end
  end

  defp pattern_vars({_name, _meta, args}) when is_list(args), do: pattern_vars(args)
  defp pattern_vars({left, right}), do: pattern_vars(left) ++ pattern_vars(right)
  defp pattern_vars(list) when is_list(list), do: Enum.flat_map(list, &pattern_vars/1)
  defp pattern_vars(_other), do: []

  defp dunder?(name) do
    name
    |> Atom.to_string()
    |> String.starts_with?("__")
  end
end
