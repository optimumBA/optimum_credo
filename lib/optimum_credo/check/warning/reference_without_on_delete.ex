defmodule OptimumCredo.Check.Warning.ReferenceWithoutOnDelete do
  @moduledoc """
  Finds `references/1,2` calls in migrations that do not state `on_delete:`.

  Without `on_delete`, Postgres defaults to `NO ACTION`: deleting a parent row fails if
  children exist. That might be right, but it should be a decision written in the migration
  (`on_delete: :nothing` counts as a decision).

  ## Parameters

  - `require_on_delete`: default `true`. Set `false` to turn the check off from shared
    configuration without removing it.
  - `ignore_files`: path suffixes or regexes of legacy migrations to skip.

  A `references` call whose options are not a literal keyword list (`references(:users, opts)`)
  is not reported because the option may be supplied there. `modify` of an existing
  column is reported like `add`, except for the `from:` option, which only describes the
  column's previous definition. `Ecto.Migration.references/2` is recognised when qualified
  or aliased (`alias Ecto.Migration`).
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [require_on_delete: true, ignore_files: []],
    explanations: [
      check: """
      Declare what happens to child rows when the referenced row is deleted.

      ## Bad

      ```elixir
      add :user_id, references(:users)
      ```

      ## Good

      ```elixir
      add :user_id, references(:users, on_delete: :delete_all)
      ```
      """,
      params: [
        require_on_delete: "Report references that do not declare on_delete.",
        ignore_files: "Path suffixes or regexes for migrations to skip."
      ]
    ]

  alias OptimumCredo.OptimumDataSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    ignore_files = Params.get(params, :ignore_files, __MODULE__)

    if Params.get(params, :require_on_delete, __MODULE__) and
         OptimumDataSupport.migration?(source_file) and
         not OptimumDataSupport.ignored_file?(source_file, ignore_files) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.SourceFile.ast()
      |> references()
      |> Enum.map(fn meta ->
        format_issue(issue_meta,
          message:
            "`references` should declare `on_delete:` (for example `:delete_all` or `:nothing`).",
          trigger: "references",
          line_no: OptimumDataSupport.line(meta)
        )
      end)
    else
      []
    end
  end

  defp references(ast) do
    ast
    |> OptimumDataSupport.expand_aliases()
    |> find([])
    |> Enum.reverse()
  end

  # `modify :x, references(:users, on_delete: :nothing), from: references(:users)`: `from:`
  # only describes the previous column definition for rollbacks, so it is not inspected.
  defp find({:modify, _meta, args}, acc) when is_list(args) do
    args
    |> Enum.map(&without_from/1)
    |> Enum.reduce(acc, &find/2)
  end

  defp find({:references, meta, [_table | rest]} = node, acc) do
    walk(
      node,
      rest
      |> missing_on_delete?()
      |> flag(meta, acc)
    )
  end

  defp find(
         {{:., _dot_meta, [{:__aliases__, _meta, [:Ecto, :Migration]}, :references]}, meta,
          [_table | rest]} = node,
         acc
       ) do
    flagged =
      rest
      |> missing_on_delete?()
      |> flag(meta, acc)

    walk(node, flagged)
  end

  defp find({_form, _meta, args} = node, acc) when is_list(args), do: walk(node, acc)
  defp find({left, right}, acc), do: find(right, find(left, acc))
  defp find(list, acc) when is_list(list), do: Enum.reduce(list, acc, &find/2)
  defp find(_other, acc), do: acc

  defp walk({form, _meta, args}, acc) do
    acc = if is_tuple(form), do: find(form, acc), else: acc
    Enum.reduce(args, acc, &find/2)
  end

  defp without_from(argument) do
    if OptimumDataSupport.keyword_literal?(argument),
      do: Keyword.delete(argument, :from),
      else: argument
  end

  defp flag(true, meta, acc), do: [meta | acc]
  defp flag(false, _meta, acc), do: acc

  defp missing_on_delete?([]), do: true

  defp missing_on_delete?([options]) do
    OptimumDataSupport.keyword_literal?(options) and
      OptimumDataSupport.fetch_option([options], :on_delete) == :error
  end

  defp missing_on_delete?(_other), do: false
end
