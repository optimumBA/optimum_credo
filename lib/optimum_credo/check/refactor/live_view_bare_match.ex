defmodule OptimumCredo.Check.Refactor.LiveViewBareMatch do
  @moduledoc """
  A check that finds bare `{:ok, _} =` and `{:error, _} =` pattern matches in
  LiveView modules.

  In LiveView callbacks, bare pattern matches on Ecto operations crash the process
  when the operation fails. All `{:ok, _} | {:error, _}` results MUST be handled
  with `case` to explicitly handle both outcomes.
  """

  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      LiveView modules must use `case` for operations that return `{:ok, _} | {:error, _}`.

      Bare pattern matches crash the LiveView process on failure and hide error handling bugs.
      Credo's `--warnings-as-errors` treats unhandled match failures as warnings in some
      configurations, and the crash surfaces as an unhelpful 500 error.

      ## Examples

      **Bad:**
      ```elixir
      def handle_event("create", params, socket) do
        {:ok, post} = Posts.create_post(params)
        {:noreply, push_navigate(socket, to: ~p"/posts")}
      end
      ```

      **Good:**
      ```elixir
      def handle_event("create", params, socket) do
        case Posts.create_post(params) do
          {:ok, _post} ->
            {:noreply, socket |> put_flash(:info, "Created") |> push_navigate(to: ~p"/posts")}
          {:error, changeset} ->
            {:noreply, assign(socket, :changeset, changeset)}
        end
      end
      ```
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

  defp traverse({:defmodule, _meta, _children} = ast, issues, issue_meta) do
    if live_view_module?(ast) do
      new_issues = find_bare_matches_in_module(ast, issue_meta)
      {ast, issues ++ new_issues}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta) do
    {ast, issues}
  end

  # Detect if a defmodule uses Phoenix.LiveView or Phoenix.LiveComponent
  defp live_view_module?({:defmodule, _meta, [_name, [do: body]]}) do
    body
    |> Macro.prewalk(false, &detect_live_view_use/2)
    |> elem(1)
  end

  defp live_view_module?(_ignored), do: false

  defp detect_live_view_use(
         {:use, _meta, [{:__aliases__, _alias_meta, [:Phoenix, :LiveView]} | _tail]},
         _acc
       ) do
    {nil, true}
  end

  defp detect_live_view_use(
         {:use, _meta, [{:__aliases__, _alias_meta, [:Phoenix, :LiveComponent]} | _tail]},
         _acc
       ) do
    {nil, true}
  end

  # Matches `use SomeWeb, :live_view` and `use SomeWeb, :live_component`
  defp detect_live_view_use(
         {:use, _meta, [_module, atom]},
         _acc
       )
       when atom in [:live_view, :live_component] do
    {nil, true}
  end

  defp detect_live_view_use(ast, acc) do
    {ast, acc}
  end

  defp find_bare_matches_in_module({:defmodule, _meta, [_name, [do: body]]}, issue_meta) do
    body
    |> Macro.prewalk([], fn ast, issues ->
      case check_bare_match(ast, issue_meta) do
        nil -> {ast, issues}
        issue -> {ast, [issue | issues]}
      end
    end)
    |> elem(1)
  end

  defp find_bare_matches_in_module(_ast, _issue_meta), do: []

  # {:ok, var} = expr
  defp check_bare_match(
         {:=, meta, [{:ok, _inner}, _rhs]},
         issue_meta
       ) do
    issue_for(issue_meta, meta[:line], "{:ok, _} =")
  end

  # {:error, var} = expr
  defp check_bare_match(
         {:=, meta, [{:error, _inner}, _rhs]},
         issue_meta
       ) do
    issue_for(issue_meta, meta[:line], "{:error, _} =")
  end

  # {:ok, var1, var2} = expr (3-tuple)
  defp check_bare_match(
         {:=, meta, [{{:ok, _meta, _args}, _inner1, _inner2}, _rhs]},
         issue_meta
       ) do
    issue_for(issue_meta, meta[:line], "{:ok, _, _} =")
  end

  defp check_bare_match(_ast, _issue_meta), do: nil

  defp issue_for(issue_meta, line_no, pattern) do
    format_issue(
      issue_meta,
      message:
        "Bare `#{pattern}` match in LiveView — use `case` to handle both :ok and :error outcomes",
      line_no: line_no || 1
    )
  end
end
