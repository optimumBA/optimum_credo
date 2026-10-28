defmodule OptimumCredo.Check.Refactor.WithElseManyClausesTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Refactor.WithElseManyClauses

  test "reports else blocks with three or more clauses" do
    """
    defmodule Sample do
      def run(x) do
        with {:ok, a} <- one(x),
             {:ok, b} <- two(a) do
          {:ok, b}
        else
          {:error, :one} -> :one
          {:error, :two} -> :two
          _ -> :other
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithElseManyClauses)
    |> assert_issue(fn issue ->
      assert issue.line_no == 3
      assert issue.message =~ "3"
    end)
  end

  test "allows short else blocks, no else, and the do: form" do
    """
    defmodule Sample do
      def a(x) do
        with {:ok, a} <- one(x) do
          a
        else
          {:error, :one} -> :one
          _ -> :other
        end
      end

      def b(x) do
        with {:ok, a} <- one(x), do: a
      end

      def c(x), do: with({:ok, a} <- one(x), do: a, else: (_ -> :error))

      def d(x) do
        case x do
          1 -> :a
          2 -> :b
          3 -> :c
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithElseManyClauses)
    |> refute_issues()
  end

  test "min_else_clauses param and nested with" do
    source = """
    defmodule Sample do
      def a(x) do
        with {:ok, a} <- one(x) do
          with {:ok, b} <- two(a) do
            b
          else
            :a -> 1
            :b -> 2
          end
        else
          :a -> 1
          :b -> 2
        end
      end
    end
    """

    source
    |> to_source_file()
    |> run_check(WithElseManyClauses)
    |> refute_issues()

    source
    |> to_source_file()
    |> run_check(WithElseManyClauses, min_else_clauses: 2)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "counts each nested with on its own, honours min_else_clauses and the inline else" do
    """
    defmodule Sample do
      def a(x) do
        with {:ok, a} <- x do
          with {:ok, b} <- a do
            b
          else
            {:error, :one} -> 1
            {:error, :two} -> 2
            _ -> 3
          end
        else
          _ -> :error
        end
      end

      def b(x), do: with({:ok, a} <- x, do: a, else: (_ -> 1))
      def c(x), do: x |> with_helper()
    end
    """
    |> to_source_file()
    |> run_check(WithElseManyClauses)
    |> assert_issue(fn issue -> assert issue.line_no == 4 end)

    """
    defmodule Sample do
      def b(x), do: with({:ok, a} <- x, do: a, else: (_ -> 1))
    end
    """
    |> to_source_file()
    |> run_check(WithElseManyClauses, min_else_clauses: 1)
    |> assert_issue(fn issue -> assert issue.message =~ "1 `else` clauses" end)
  end
end
