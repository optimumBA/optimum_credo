defmodule OptimumCredo.Check.Readability.FunctionOrderTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.FunctionOrder

  test "reports unsorted public functions once with the first offender" do
    """
    defmodule Demo do
      def update(x), do: x
      def create(x), do: x
      def delete(x), do: x
    end
    """
    |> to_source_file()
    |> run_check(FunctionOrder, function_order: :alphabetical)
    |> assert_issue(fn issue ->
      assert issue.line_no == 3
      assert issue.message =~ "public function create before update"
    end)
  end

  test "orders public and private groups independently" do
    """
    defmodule Demo do
      def a(x), do: b(x) + c(x) + z(x)
      def m(x), do: x
      def z(x), do: x

      defp c(x), do: x
      defp b(x), do: x
      defp d(x), do: x
    end
    """
    |> to_source_file()
    |> run_check(FunctionOrder, function_order: :alphabetical)
    |> assert_issue(fn issue ->
      assert issue.line_no == 7
      assert issue.message =~ "private function b before c"
    end)
  end

  test "multiple clauses and arities of one name stay a single unit" do
    """
    defmodule Demo do
      def a(1), do: 1
      def a(2), do: 2
      def b(x, y), do: {x, y}
      def b(x), do: x
      def c(x), do: x
    end
    """
    |> to_source_file()
    |> run_check(FunctionOrder, function_order: :alphabetical)
    |> refute_issues()
  end

  test "skips @impl callbacks and respects min_run" do
    source = """
    defmodule Demo do
      @impl true
      def init(x), do: x
      @impl true
      def handle_call(_a, _b, x), do: x
      def zeta(x), do: x
      def alpha(x), do: x
    end
    """

    source
    |> to_source_file()
    |> run_check(FunctionOrder, function_order: :alphabetical)
    |> refute_issues()

    source
    |> to_source_file()
    |> run_check(FunctionOrder, function_order: :alphabetical, min_run: 2)
    |> assert_issue()
  end

  test "defaults to :off and does nothing without an explicit mode" do
    "defmodule D do\n  def b(x), do: x\n  def a(x), do: x\n  def c(x), do: x\n  defp z, do: 1\n  defp y, do: z()\nend"
    |> to_source_file()
    |> run_check(FunctionOrder)
    |> refute_issues()
  end

  test ":off disables the check explicitly and string modes are accepted" do
    source = "defmodule D do\n  def b(x), do: x\n  def a(x), do: x\n  def c(x), do: x\nend"

    source
    |> to_source_file()
    |> run_check(FunctionOrder, function_order: :off)
    |> refute_issues()

    source
    |> to_source_file()
    |> run_check(FunctionOrder, function_order: "off")
    |> refute_issues()

    source
    |> to_source_file()
    |> run_check(FunctionOrder, function_order: "alphabetical")
    |> assert_issue()
  end

  test "an invalid mode raises instead of silently choosing a policy" do
    source = "defmodule D do\n  def b(x), do: x\n  def a(x), do: x\n  def c(x), do: x\nend"

    for mode <- [:weird, :alpha, "Alphabetical", 1] do
      assert_raise ArgumentError, ~r/invalid function_order/, fn ->
        source
        |> to_source_file()
        |> FunctionOrder.run(function_order: mode)
      end
    end
  end

  test "@impl covers only its own name and arity" do
    """
    defmodule Demo do
      @impl true
      def handle_event(a, b, c), do: {a, b, c}
      def zeta(x), do: x
      def handle_event(x), do: x
      def alpha(x), do: x
    end
    """
    |> to_source_file()
    |> run_check(FunctionOrder, function_order: :alphabetical)
    |> assert_issue(fn issue ->
      assert issue.message =~ "handle_event before zeta"
    end)
  end

  test "an @impl callback of another arity does not hide an unsorted helper" do
    """
    defmodule Demo do
      @impl true
      def render(a), do: a
      def zeta(x), do: x
      def render(a, b), do: {a, b}
      def alpha(x), do: x
    end
    """
    |> to_source_file()
    |> run_check(FunctionOrder, function_order: :alphabetical, min_run: 3)
    |> assert_issue(fn issue -> assert issue.message =~ "render before zeta" end)
  end

  test ":callers_first reports a private function defined above its caller" do
    """
    defmodule Demo do
      defp helper(x), do: x

      def run(x), do: helper(x)
    end
    """
    |> to_source_file()
    |> run_check(FunctionOrder, function_order: :callers_first)
    |> assert_issue(fn issue ->
      assert issue.line_no == 2
      assert issue.message =~ "helper/1 below its first caller run/1"
    end)
  end

  test ":callers_first accepts callers above, captures, pipes and uncalled functions" do
    """
    defmodule Demo do
      def run(x) do
        x |> first() |> Enum.map(&second/1)
      end

      defp first(x), do: x
      defp second(x), do: x
      defp unused(x), do: x
    end
    """
    |> to_source_file()
    |> run_check(FunctionOrder, function_order: :callers_first)
    |> refute_issues()
  end

  test ":callers_first ignores self recursion, public functions and strings" do
    """
    defmodule Demo do
      def helper(x), do: x

      defp loop(x), do: loop(x)

      def run(x), do: "loop(helper)" <> x
    end
    """
    |> to_source_file()
    |> run_check(FunctionOrder, function_order: :callers_first)
    |> refute_issues()
  end

  test "handles nested modules separately" do
    """
    defmodule Outer do
      defmodule Inner do
        def b(x), do: x
        def a(x), do: x
        def c(x), do: x
      end

      def z(x), do: x
    end
    """
    |> to_source_file()
    |> run_check(FunctionOrder, function_order: :alphabetical)
    |> assert_issue(fn issue -> assert issue.line_no == 4 end)
  end

  test ":callers_first matches callers by name and arity" do
    """
    defmodule Demo do
      defp helper(x, y), do: {x, y}

      def run(x), do: helper(x)

      defp helper(x), do: x
    end
    """
    |> to_source_file()
    |> run_check(FunctionOrder, function_order: :callers_first)
    |> refute_issues()
  end

  test ":callers_first counts a piped value as an argument and default arities" do
    source = """
    defmodule Demo do
      defp helper(x, y \\\\ 1), do: {x, y}

      def run(x), do: x |> helper()
    end
    """

    source
    |> to_source_file()
    |> run_check(FunctionOrder, function_order: :callers_first)
    |> assert_issue(fn issue ->
      assert issue.message =~ "helper/2 below its first caller run/1"
    end)

    """
    defmodule Demo do
      defp helper(x, y, z), do: {x, y, z}

      def run(x), do: x |> helper()
    end
    """
    |> to_source_file()
    |> run_check(FunctionOrder, function_order: :callers_first)
    |> refute_issues()
  end

  test ":callers_first ignores calls in quote and counts @impl callbacks as callers" do
    """
    defmodule Demo do
      defp quoted(x), do: x
      defp from_callback(x), do: x

      defmacro __using__(_opts) do
        quote do
          quoted(1)
        end
      end

      @impl true
      def init(x), do: from_callback(x)
    end
    """
    |> to_source_file()
    |> run_check(FunctionOrder, function_order: :callers_first)
    |> assert_issue(fn issue ->
      assert issue.line_no == 3
      assert issue.message =~ "from_callback/1 below its first caller init/1"
    end)
  end

  test ":callers_first sees calls in guards, rescue and after blocks" do
    """
    defmodule Demo do
      defp cleanup, do: :ok

      def run(x) do
        x
      rescue
        _ -> :error
      after
        cleanup()
      end
    end
    """
    |> to_source_file()
    |> run_check(FunctionOrder, function_order: :callers_first)
    |> assert_issue(fn issue ->
      assert issue.message =~ "cleanup/0 below its first caller run/1"
    end)
  end
end
