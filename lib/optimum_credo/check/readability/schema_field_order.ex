defmodule OptimumCredo.Check.Readability.SchemaFieldOrder do
  @moduledoc """
  Finds Ecto schema fields and associations that are not in alphabetical order.

  Inside `schema`, `embedded_schema`, and `embeds_one`/`embeds_many` blocks,
  consecutive `field`, `belongs_to`, `has_one`, `has_many`, `many_to_many`,
  `embeds_one`, and `embeds_many` declarations form a run. Any other statement
  (`timestamps()`, a module attribute, a call with a dynamic name) ends the run.
  The first declaration in a run that sorts before its predecessor is reported,
  once per run.

  Declarations are compared by the name written in the macro (`belongs_to :user`
  sorts as `user`, not `user_id`). This is a static, conservative heuristic and does
  not understand when a different order is intentional.

  ## Parameters

  - `min_run`: minimum number of consecutive declarations a run needs (default `3`).
  - `group_associations`: when true, fields and associations are ordered as two
    separate groups and may be interleaved.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [min_run: 3, group_associations: false],
    explanations: [
      check: """
      Keep schema fields in alphabetical order so entries are predictable.

      ## Bad

      ```elixir
      schema "posts" do
        field :title, :string
        field :body, :string
        field :author, :string
      end
      ```

      ## Good

      ```elixir
      schema "posts" do
        field :author, :string
        field :body, :string
        field :title, :string
      end
      ```

      A run must be at least `min_run` long. With `group_associations: true`, fields
      and associations are checked as separate groups.
      """,
      params: [
        min_run: "Minimum consecutive declarations needed before order is checked.",
        group_associations: "Order fields and associations as separate groups."
      ]
    ]

  alias OptimumCredo.OptimumStructureSupport

  @fields [:field]
  @associations [:belongs_to, :has_one, :has_many, :many_to_many, :embeds_one, :embeds_many]
  @blocks [:schema, :embedded_schema, :embeds_one, :embeds_many]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    min_run = Params.get(params, :min_run, __MODULE__)
    grouped? = Params.get(params, :group_associations, __MODULE__)

    source_file
    |> Credo.Code.prewalk(fn
      {block, _meta, args} = ast, issues when block in @blocks and is_list(args) ->
        {ast, scan(args, min_run, grouped?, issue_meta) ++ issues}

      ast, issues ->
        {ast, issues}
    end)
    |> Enum.reverse()
  end

  defp scan(args, min_run, grouped?, issue_meta) do
    case List.last(args) do
      [do: body] ->
        body
        |> OptimumStructureSupport.statements()
        |> issues(min_run, grouped?, issue_meta)

      _other ->
        []
    end
  end

  defp issues(statements, min_run, grouped?, issue_meta) do
    statements
    |> OptimumStructureSupport.runs(&classify/1, 1)
    |> Enum.flat_map(&partition(&1, grouped?))
    |> Enum.filter(&(length(&1) >= min_run))
    |> Enum.flat_map(fn run ->
      entries = Enum.map(run, fn {{_kind, name}, line} -> {name, line} end)

      case OptimumStructureSupport.first_unsorted(entries) do
        {previous, current, line} ->
          [
            format_issue(issue_meta,
              message:
                "Declare #{current} before #{previous} to keep schema entries alphabetical.",
              line_no: line
            )
          ]

        nil ->
          []
      end
    end)
  end

  defp partition(run, false), do: [run]

  defp partition(run, true) do
    run
    |> Enum.split_with(fn {{kind, _name}, _line} -> kind == :field end)
    |> Tuple.to_list()
  end

  defp classify({macro, meta, [name | _rest]}) when macro in @fields or macro in @associations do
    if is_atom(name) and not is_nil(name) do
      kind = if macro in @fields, do: :field, else: :association
      {{kind, Atom.to_string(name)}, meta[:line] || 1}
    end
  end

  defp classify(_statement), do: nil
end
