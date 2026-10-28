defmodule OptimumCredo.Check.Warning.SeedInsertWithoutOnConflict do
  @moduledoc """
  Finds `Repo.insert/2`, `Repo.insert!/2` and `Repo.insert_all/3` calls in seed files that
  have no `on_conflict:` option.

  Seeds are meant to be runnable any number of times. A plain insert raises (or duplicates
  rows) the second time. Pass `on_conflict: :nothing` / `{:replace, fields}` with a
  `conflict_target:`, or look the row up first.

  Seed files are the paths in `seed_paths` (default `priv/repo/seeds.exs` and everything
  under `priv/repo/seeds/`). Only calls on a module whose last segment is `Repo` are read, after following aliases
  (`alias MyApp.Repo, as: R`).

  Accepted without `on_conflict:`: an insert inside a branch whose condition looks the row up
  with `Repo.get*`, `Repo.one*`, `Repo.exists?` or `Repo.all` (`Repo.get_by(...) || Repo.insert!(...)`,
  `if Repo.exists?(...)`, `case Repo.get(...)`), and calls whose options are passed as a
  variable. `on_conflict: :raise` counts as missing.

  ## Parameters

  - `seed_paths`: file suffixes or directories (ending in `/`) that are seed files.

  Seeds that call context functions (`Accounts.create_user/1`) are not inspected.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [seed_paths: ["priv/repo/seeds.exs", "priv/repo/seeds/"]],
    explanations: [
      check: """
      Seed inserts should be idempotent.

      ## Bad

      ```elixir
      Repo.insert!(%Role{name: "admin"})
      ```

      ## Good

      ```elixir
      Repo.insert!(%Role{name: "admin"}, on_conflict: :nothing, conflict_target: :name)
      ```
      """,
      params: [seed_paths: "Seed file path suffixes, or directories ending in `/`."]
    ]

  alias OptimumCredo.OptimumDataSupport

  @lookups [:get, :get!, :get_by, :get_by!, :one, :one!, :exists?, :all, :aggregate]
  # Positional arguments before the options list.
  @inserts %{insert: 1, insert!: 1, insert_all: 2}

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    if seed_file?(source_file, Params.get(params, :seed_paths, __MODULE__)) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.SourceFile.ast()
      |> OptimumDataSupport.expand_aliases()
      |> mark_piped()
      |> OptimumDataSupport.unguarded_nodes(&lookup?/1, &insert_without_on_conflict?/1)
      |> Enum.map(fn {{:., _meta, [_repo, function]}, meta, _args} ->
        format_issue(issue_meta,
          message:
            "Seed `Repo.#{function}` has no `on_conflict:`; running the seeds twice will fail or duplicate rows.",
          trigger: "Repo.#{function}",
          line_no: OptimumDataSupport.line(meta)
        )
      end)
    else
      []
    end
  end

  defp seed_file?(source_file, paths) do
    paths
    |> List.wrap()
    |> Enum.any?(fn path ->
      if String.ends_with?(path, "/"),
        do: OptimumDataSupport.in_dir?(source_file, path),
        else: OptimumDataSupport.ends_with_path?(source_file, path)
    end)
  end

  defp lookup?(node) do
    match?({:repo, function, _, _} when function in @lookups, repo_call(node))
  end

  defp insert_without_on_conflict?(node) do
    case repo_call(node) do
      {:repo, function, args, meta} when is_map_key(@inserts, function) ->
        # `changeset |> Repo.insert!(opts)` has one argument fewer than the positional count.
        positional = Map.fetch!(@inserts, function) - if(meta[:piped], do: 1, else: 0)

        case OptimumDataSupport.fetch_option(args, :on_conflict) do
          {:ok, :raise} -> true
          {:ok, _strategy} -> false
          :error -> not opaque_options?(args, positional)
        end

      _other ->
        false
    end
  end

  defp mark_piped(ast) do
    Macro.prewalk(ast, fn
      {:|>, meta, [left, {{:., _meta, _args} = callee, call_meta, args}]} when is_list(args) ->
        {:|>, meta, [left, {callee, Keyword.put(call_meta, :piped, true), args}]}

      node ->
        node
    end)
  end

  # More arguments than positional ones and no keyword literal: the options are a variable.
  defp opaque_options?(args, positional) do
    last = List.last(args)
    length(args) > positional and not OptimumDataSupport.keyword_literal?(last)
  end

  defp repo_call({{:., _meta, [module, function]}, meta, args} = _node) when is_list(args) do
    if OptimumDataSupport.last_segment(module) == :Repo, do: {:repo, function, args, meta}
  end

  defp repo_call(_node), do: nil
end
