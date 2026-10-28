defmodule OptimumCredo.Check.Readability.CastListOrder do
  @moduledoc """
  Finds literal field lists passed to changeset functions that are not alphabetical.

  Checks the first literal list of atoms (or of strings) passed to `cast` or
  `validate_required` (configurable through `functions`). Both direct and piped
  calls are supported, as are remote calls on `Changeset` / `Ecto.Changeset`.

  Unqualified calls are only treated as Ecto's when the file imports or uses one of the
  modules in `changeset_imports` (`import Ecto.Changeset` by default), so an unrelated
  local `cast/3` or a `cast` function of another library is left alone. Remote calls are
  inspected when the module's last segment is `Changeset` (`Ecto.Changeset.cast`, or an
  alias such as `Changeset.cast`). If your schemas get the changeset functions through a
  macro (`use MyApp.Schema`), list that module in `changeset_imports` or set
  `local_calls: :always`.

  This is a static heuristic: lists built from variables or module attributes are not
  inspected (see `ModuleAttributeListOrder`), and lists mixing atoms with other terms are
  skipped.

  ## Parameters

  - `min_run`: minimum list length to check (default `3`).
  - `functions`: changeset function names to inspect.
  - `local_calls`: `:imported` (default) inspects unqualified calls only in files that
    import or use a module from `changeset_imports`; `:always` inspects every unqualified
    call; `:never` inspects remote `Changeset` calls only.
  - `changeset_imports`: modules whose `import`/`use` brings the changeset functions into
    scope (default `["Ecto.Changeset"]`).
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [
      min_run: 3,
      functions: [:cast, :validate_required],
      local_calls: :imported,
      changeset_imports: ["Ecto.Changeset"]
    ],
    explanations: [
      check: """
      Keep field lists passed to `cast/3` and `validate_required/2` alphabetical.

      ## Bad

      ```elixir
      cast(user, attrs, [:name, :email, :age])
      ```

      ## Good

      ```elixir
      cast(user, attrs, [:age, :email, :name])
      ```

      Only literal lists with at least `min_run` atoms (or strings) are checked.
      Unqualified calls count when the file has `import Ecto.Changeset` (configurable).
      """,
      params: [
        min_run: "Minimum list length that is checked.",
        functions: "Changeset function names to inspect."
      ]
    ]

  alias OptimumCredo.OptimumStructureSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    min_run = Params.get(params, :min_run, __MODULE__)

    functions =
      params
      |> Params.get(:functions, __MODULE__)
      |> OptimumStructureSupport.to_strings()

    mode =
      params
      |> Params.get(:local_calls, __MODULE__)
      |> mode!()

    imports =
      params
      |> Params.get(:changeset_imports, __MODULE__)
      |> OptimumStructureSupport.to_strings()

    local? = local_calls?(mode, source_file, imports)

    source_file
    |> Credo.Code.prewalk(fn ast, issues ->
      {ast, check_call(ast, functions, min_run, local?, issue_meta) ++ issues}
    end)
    |> Enum.reverse()
  end

  defp mode!(mode) when mode in [:imported, :always, :never], do: mode
  defp mode!("imported"), do: :imported
  defp mode!("always"), do: :always
  defp mode!("never"), do: :never

  defp mode!(mode) do
    raise ArgumentError,
          "invalid local_calls #{inspect(mode)} for #{inspect(__MODULE__)}; " <>
            "use :imported, :always or :never"
  end

  defp local_calls?(:always, _source_file, _imports), do: true
  defp local_calls?(:never, _source_file, _imports), do: false

  defp local_calls?(:imported, source_file, imports) do
    Credo.Code.prewalk(
      source_file,
      fn
        {kind, _meta, [target | _tail]} = ast, found? when kind in [:import, :use] ->
          {ast, found? or imported?(target, imports)}

        ast, found? ->
          {ast, found?}
      end,
      false
    )
  end

  defp imported?(target, imports) do
    case OptimumStructureSupport.alias_segments(target) do
      nil -> false
      segments -> Enum.map_join(segments, ".", &Atom.to_string/1) in imports
    end
  end

  defp unsorted_names(args, min_run) do
    with names when is_list(names) and length(names) >= min_run <-
           Enum.find_value(args, &OptimumStructureSupport.literal_names/1) do
      names
      |> Enum.map(fn {name, _value} -> {name, 0} end)
      |> OptimumStructureSupport.first_unsorted()
    end
  end

  defp check_call(ast, functions, min_run, local?, issue_meta) do
    with {name, meta, args} when is_list(args) <- call(ast, local?),
         true <- Atom.to_string(name) in functions,
         {previous, current, _line} <- unsorted_names(args, min_run) do
      [
        format_issue(issue_meta,
          message:
            "Put #{current} before #{previous} in the #{name} list to keep it alphabetical.",
          line_no: meta[:line] || 1
        )
      ]
    else
      _other -> []
    end
  end

  defp call({{:., _dot, [module, name]}, meta, args}, _local?) when is_atom(name) do
    if changeset_module?(module), do: {name, meta, args}
  end

  defp call({name, meta, args}, true) when is_atom(name) and is_list(args), do: {name, meta, args}
  defp call(_ast, _local?), do: nil

  defp changeset_module?({:__aliases__, _meta, segments}), do: List.last(segments) == :Changeset
  defp changeset_module?(_module), do: false
end
