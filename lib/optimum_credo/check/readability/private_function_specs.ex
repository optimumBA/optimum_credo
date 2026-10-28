defmodule OptimumCredo.Check.Readability.PrivateFunctionSpecs do
  @moduledoc """
  A check that finds @spec declarations for private functions (defp).

  Private functions should not have @spec declarations as they are internal
  implementation details and not part of the module's public API.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    explanations: [
      check: """
      Private functions should not have @spec declarations. Specs are for
      public API documentation and type checking, not internal implementation details.

      ## Examples

      **Bad:**
      ```elixir
      @spec lookup_cached_entries(list()) :: {:hit, content()} | :miss
      defp lookup_cached_entries(ets_match_spec) do
        # ...
      end
      ```

      **Good:**
      ```elixir
      defp lookup_cached_entries(ets_match_spec) do
        # ...
      end
      ```

      Only public functions (def) should have @spec declarations.
      """
    ]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(
      source_file,
      &traverse(&1, &2, issue_meta)
    )
  end

  defp traverse({:defmodule, _meta, [_name, [do: body]]} = ast, issues, issue_meta) do
    {ast, issues ++ check_private_function_specs(body, issue_meta)}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp check_private_function_specs(body, issue_meta) do
    nodes = module_nodes(body)

    public =
      nodes
      |> Enum.flat_map(&function_arities(&1, :def))
      |> MapSet.new()

    private =
      nodes
      |> Enum.flat_map(&function_arities(&1, :defp))
      |> MapSet.new()

    # A spec belongs to a private function only when no public function shares
    # its name and arity: `def f/2` may delegate to a private `defp f/3`.
    for {:@, meta, [{:spec, _meta, [spec]}]} <- nodes,
        {name, arity} = spec_signature(spec),
        name,
        MapSet.member?(private, {name, arity}),
        not MapSet.member?(public, {name, arity}) do
      issue_for(
        issue_meta,
        meta[:line] || 1,
        "Remove @spec for private function #{name}/#{arity}. " <>
          "Private functions should not have @spec declarations."
      )
    end
  end

  # Nodes of this module's own body (including compile-time conditionals), but
  # not nested modules or quoted code, which define other modules' functions.
  defp module_nodes(body) do
    {_ast, nodes} =
      Macro.prewalk(body, [], fn
        {:defmodule, _meta, _args}, nodes -> {:skip, nodes}
        {:quote, _meta, _args}, nodes -> {:skip, nodes}
        node, nodes -> {node, [node | nodes]}
      end)

    Enum.reverse(nodes)
  end

  defp spec_signature({:when, _meta, [spec | _tail]}), do: spec_signature(spec)

  defp spec_signature({:"::", _meta, [{name, _tuple_meta, args} | _tail]}) when is_atom(name) do
    {name, if(is_list(args), do: length(args), else: 0)}
  end

  defp spec_signature(_ignored), do: {nil, 0}

  # Every arity a definition answers to, taking default arguments into account.
  defp function_arities({kind, _meta, [head | _tail]}, kind) do
    case head do
      {:when, _meta, [head | _tail]} -> arities_of_head(head)
      head -> arities_of_head(head)
    end
  end

  defp function_arities(_ignored, _kind), do: []

  defp arities_of_head({name, _meta, args}) when is_atom(name) do
    args = if is_list(args), do: args, else: []
    defaults = Enum.count(args, &match?({:"\\\\", _meta, _args}, &1))
    for arity <- (length(args) - defaults)..length(args), do: {name, arity}
  end

  defp arities_of_head(_ignored), do: []

  defp issue_for(issue_meta, line_no, message) do
    format_issue(
      issue_meta,
      message: message,
      line_no: line_no
    )
  end
end
