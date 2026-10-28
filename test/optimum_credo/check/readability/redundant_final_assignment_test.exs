defmodule OptimumCredo.Check.Readability.RedundantFinalAssignmentTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.RedundantFinalAssignment

  test "reports a value assigned and returned immediately" do
    """
    defmodule Sample do
      def total(items) do
        prepare()
        total = Enum.sum(items)
        total
      end

      defp other(x) do
        result = x + 1
        result
      end

      defmacro macro(x) do
        value = x
        value
      end
    end
    """
    |> to_source_file()
    |> run_check(RedundantFinalAssignment)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [4, 9, 14] end)
  end

  test "reports guarded heads" do
    """
    defmodule Sample do
      def total(items) when is_list(items) do
        total = Enum.sum(items)
        total
      end
    end
    """
    |> to_source_file()
    |> run_check(RedundantFinalAssignment)
    |> assert_issue()
  end

  test "ignores different variables, patterns, later use and non-final positions" do
    """
    defmodule Sample do
      def a(x) do
        y = x + 1
        z
      end

      def b(x) do
        {:ok, y} = fetch(x)
        y
      end

      def c(x) do
        y = x + 1
        log(y)
        y
      end

      def d(x) do
        y = x + 1
        y
        :done
      end

      def e(x), do: x

      def f(x) do
        fun = fn -> y = x; y end
        fun.()
      end

      def g(x) do
        _ = side_effect(x)
        x
      end

      def h(x) do
        y = x
        ^y = x
      end
    end
    """
    |> to_source_file()
    |> run_check(RedundantFinalAssignment)
    |> refute_issues()
  end

  test "reports rescue-bearing bodies, macros and one-line blocks; leaves later uses alone" do
    """
    defmodule Sample do
      def a(x) do
        result = risky(x)
        result
      rescue
        _ -> :error
      end

      defmacro b(x) do
        quoted = quote do: unquote(x)
        quoted
      end

      def c(x), do: (value = x; value)

      def d(x) do
        value = x
        other = value
        value
      end

      def e(x) do
        value = x
        fun = fn -> value end
        fun.()
        value
      end

      def f(x) do
        {a, b} = x
        {a, b}
      end
    end
    """
    |> to_source_file()
    |> run_check(RedundantFinalAssignment)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [3, 10, 14] end)
  end

  test "a different variable on the last line, and anonymous functions and case branches" do
    """
    defmodule Sample do
      def a(x) do
        first = x
        second = first
        first
      end

      def b(x) do
        Enum.map(x, fn item ->
          doubled = item * 2
          doubled
        end)
      end

      def c(x) do
        case x do
          :a ->
            result = 1
            result
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(RedundantFinalAssignment)
    |> refute_issues()
  end
end
