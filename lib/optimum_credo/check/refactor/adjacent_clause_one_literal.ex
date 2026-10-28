defmodule OptimumCredo.Check.Refactor.AdjacentClauseOneLiteral do
  @moduledoc """
  Finds two adjacent clauses of one function that differ only in a single literal value.

  Two consecutive `def`/`defp` clauses with the same name and arity are compared
  structurally (ignoring line numbers). When every difference is the same literal pair
  (for example `:a` in one clause and `:b` in the other, wherever it occurs), the clauses
  are candidates for one parameterised clause. Clauses whose bodies have fewer than
  `min_nodes` AST call nodes are skipped, as are clauses that differ in variables, structure, or
  more than one literal pair.

  Differences that exist only in the function head (for example two binary prefixes handled by
  an identical body) are not reported: the literal never reaches the body, so it cannot become
  a parameter. The literal must differ in the body too.

  This is a duplication hint; separate clauses can be the more readable choice.

  ## Parameters

  - `min_nodes`: smallest clause size (counted in AST call nodes) worth reporting (default `6`).
  """

  use Credo.Check,
    base_priority: :low,
    category: :refactor,
    param_defaults: [min_nodes: 6],
    explanations: [
      check: """
      Adjacent clauses that differ only in one literal value can often become one clause with
      a parameter. Reported when the only differences are a single literal pair; small clauses
      are skipped. Readable separate clauses are a valid choice. Opt-in, low priority.

      ## Bad

      ```elixir
      def sort(:name), do: Repo.all(from(u in User, where: u.active, order_by: field(u, :name)))
      def sort(:email), do: Repo.all(from(u in User, where: u.active, order_by: field(u, :email)))
      ```

      The two clauses differ only in `:name` / `:email`, so one clause with a parameter
      (`def sort(key)`) is enough.
      """,
      params: [min_nodes: "Smallest clause size, in AST call nodes, that is reported."]
    ]

  alias OptimumCredo.OptimumIdiomsSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    min_nodes = Params.get(params, :min_nodes, __MODULE__)

    Credo.Code.prewalk(source_file, fn
      {:defmodule, _meta, [_name, [do: body]]} = node, acc ->
        {node, acc ++ module_issues(body, min_nodes, issue_meta)}

      node, acc ->
        {node, acc}
    end)
  end

  defp module_issues({:__block__, _meta, statements}, min_nodes, issue_meta) do
    statements
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [first, second] -> pair_issues(first, second, min_nodes, issue_meta) end)
  end

  defp module_issues(_body, _min_nodes, _issue_meta), do: []

  defp pair_issues(first, second, min_nodes, issue_meta) do
    signature = signature(first)

    with true <- signature != nil and signature == signature(second),
         first_ast = OptimumIdiomsSupport.strip_meta(first),
         second_ast = OptimumIdiomsSupport.strip_meta(second),
         diffs when is_list(diffs) <- differences(first_ast, second_ast),
         [_single_pair] <- Enum.uniq(diffs),
         true <- differs_in_body?(first_ast, second_ast),
         true <- node_count(second_ast) >= min_nodes do
      {_kind, meta, _args} = second
      {name, arity} = signature

      [
        format_issue(issue_meta,
          message:
            "Adjacent clauses of `#{name}/#{arity}` differ only in one literal; consider one parameterised clause.",
          line_no: meta[:line] || 1
        )
      ]
    else
      _other -> []
    end
  end

  # A literal that only differs in the head patterns (`def f("a", x)` / `def f("b", x)`) never
  # reaches the body, so there is nothing to turn into a parameter.
  defp differs_in_body?(
         {_form, _meta, [_head_a, body_a]},
         {_tuple_form, _tuple_meta, [_head_b, body_b]}
       ),
       do: differences(body_a, body_b) not in [[], :error]

  defp signature({kind, _meta, [head, _body]}) when kind in [:def, :defp],
    do: head_signature(head)

  defp signature(_statement), do: nil

  defp head_signature({:when, _meta, [head | _tail]}), do: head_signature(head)

  defp head_signature({name, _meta, args}) when is_atom(name) and is_list(args),
    do: {name, length(args)}

  defp head_signature(_head), do: nil

  # Returns the list of differing literal pairs, or `:error` when the trees differ otherwise.
  defp differences(same, same), do: []

  defp differences({form_a, [], args_a}, {form_b, [], args_b})
       when is_list(args_a) and is_list(args_b),
       do: combine([differences(form_a, form_b), differences(args_a, args_b)], form_a, form_b)

  defp differences({_form, [], context_a}, {_tuple_form, [], context_b})
       when is_atom(context_a) and is_atom(context_b),
       do: :error

  defp differences(a, b) when is_tuple(a) and is_tuple(b) and tuple_size(a) == tuple_size(b) do
    a
    |> Tuple.to_list()
    |> differences(Tuple.to_list(b))
  end

  defp differences([a | rest_a], [b | rest_b]),
    do: combine([differences(a, b), differences(rest_a, rest_b)])

  defp differences(a, b) do
    if literal?(a) and literal?(b), do: [{a, b}], else: :error
  end

  # A call's operator must be identical; only argument literals may differ.
  defp combine(results, form_a, form_b) do
    if is_atom(form_a) and form_a != form_b, do: :error, else: combine(results)
  end

  defp combine(results) do
    if :error in results, do: :error, else: List.flatten(results)
  end

  defp literal?(value), do: is_atom(value) or is_binary(value) or is_number(value)

  defp node_count(ast) do
    ast
    |> Macro.prewalk(0, fn
      {_form, _meta, args} = node, count when is_list(args) -> {node, count + 1}
      node, count -> {node, count}
    end)
    |> elem(1)
  end
end
