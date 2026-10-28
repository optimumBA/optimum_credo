defmodule OptimumCredo.Check.Refactor.RepeatedLiteralTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Refactor.RepeatedLiteral

  @repeated """
  defmodule Sample do
    def a, do: put("session_token", 1)
    def b, do: get("session_token")
    def c, do: delete("session_token")
    def d, do: "once only"
  end
  """

  test "reports a string repeated three times, once at its first use" do
    @repeated
    |> to_source_file("lib/sample.ex")
    |> run_check(RepeatedLiteral)
    |> assert_issue(fn issue ->
      assert issue.line_no == 2
      assert issue.message =~ "session_token"
      assert issue.message =~ "3 times"
    end)
  end

  test "skips tests and priv by default; ignore_paths is configurable" do
    @repeated
    |> to_source_file("test/sample_test.exs")
    |> run_check(RepeatedLiteral)
    |> refute_issues()

    @repeated
    |> to_source_file("lib/sample.ex")
    |> run_check(RepeatedLiteral, ignore_paths: ["lib/"])
    |> refute_issues()

    @repeated
    |> to_source_file("test/sample_test.exs")
    |> run_check(RepeatedLiteral, ignore_paths: [])
    |> assert_issue()
  end

  test "params: min_occurrences, min_length, ignore_literals" do
    @repeated
    |> to_source_file("lib/sample.ex")
    |> run_check(RepeatedLiteral, min_occurrences: 4)
    |> refute_issues()

    @repeated
    |> to_source_file("lib/sample.ex")
    |> run_check(RepeatedLiteral, min_length: 20)
    |> refute_issues()

    @repeated
    |> to_source_file("lib/sample.ex")
    |> run_check(RepeatedLiteral, ignore_literals: ["session_token"])
    |> refute_issues()
  end

  test "ignores attributes, patterns, heads, interpolation, sigils, imports and short strings" do
    ~S'''
    defmodule Sample do
      @a "repeated_value"
      @b "repeated_value"
      @c "repeated_value"
      @doc "repeated_value repeated_value"

      def f("repeated_value"), do: 1
      def g("repeated_value"), do: 2
      def h("repeated_value"), do: 3

      def i(x) do
        case x do
          "repeated_value" -> 1
          "repeated_value" -> 2
          "repeated_value" -> 3
        end
      end

      def j(x) do
        {"ab", "ab", "ab"}
        "repeated_value#{x}"
        "repeated_value#{x}"
        "repeated_value#{x}"
        ~s(repeated_value) <> ~s(repeated_value) <> ~s(repeated_value)
        {~H"repeated_value", ~H"repeated_value", ~H"repeated_value"}
      end
    end
    '''
    |> to_source_file("lib/sample.ex")
    |> run_check(RepeatedLiteral)
    |> refute_issues()
  end

  test "counts nested modules separately and the same literal in a pattern is not an expression" do
    """
    defmodule Outer do
      def a, do: put("session_token")
      def b, do: put("session_token")

      defmodule Inner do
        def c, do: put("session_token")
      end
    end
    """
    |> to_source_file("lib/outer.ex")
    |> run_check(RepeatedLiteral)
    |> refute_issues()
  end

  test "patterns on the left of = and <- are not expressions" do
    """
    defmodule Sample do
      def run(a) do
        with {:ok, "pending"} <- a, {:ok, "pending"} <- a, {:ok, "pending"} <- a, do: :ok
        for "active" <- a, "active" <- a, "active" <- a, do: 1
        %{kind: "paid"} = a
        %{kind: "paid"} = a
        %{kind: "paid"} = a
      end
    end
    """
    |> to_source_file()
    |> run_check(RepeatedLiteral)
    |> refute_issues()
  end

  test "counts a literal in a with/for expression side and in case bodies" do
    """
    defmodule Sample do
      def run(a, b) do
        with {:ok, x} <- fetch(a, "status") do
          case b do
            :one -> Map.get(x, "status")
            :two -> Map.get(x, "status")
          end
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(RepeatedLiteral)
    |> assert_issue(fn issue -> assert issue.message =~ "\"status\" appears 3 times" end)
  end

  test "reports each repeated literal once, sorted by its first line" do
    """
    defmodule Sample do
      def run(x) do
        log("beta")
        log("beta")
        log("beta")
        log("alpha")
        log("alpha")
        log("alpha")
      end
    end
    """
    |> to_source_file()
    |> run_check(RepeatedLiteral)
    |> assert_issues(fn issues ->
      assert [first, second] = issues
      assert first.message =~ "\"beta\" appears 3 times"
      assert second.message =~ "\"alpha\" appears 3 times"
      assert first.line_no < second.line_no
      assert {first.line_no, second.line_no} == {3, 6}
    end)
  end

  test "map keys, Access keys and attr/slot/plug declarations are not magic values" do
    """
    defmodule Sample do
      attr :class, :string, default: "h-5 w-5"
      attr :size, :string, default: "h-5 w-5"
      attr :icon, :string, default: "h-5 w-5"
      slot :inner, doc: "h-5 w-5"

      plug :accepts, ["json"]
      plug :other, ["json"]
      plug :third, ["json"]

      def a(params), do: %{"url" => params["data"], "@type" => "Thing"}
      def b(params), do: %{"url" => params["data"], "@type" => "Thing"}
      def c(params), do: %{"url" => params["data"], "@type" => "Thing"}
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(RepeatedLiteral)
    |> assert_issue(fn issue -> assert issue.message =~ "\"Thing\"" end)
  end

  test "map values and plain call arguments still count next to map keys" do
    """
    defmodule Sample do
      def a(params), do: %{"state" => "pending", other: get(params, "pending")}
      def b, do: %{"state" => "pending"}
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(RepeatedLiteral)
    |> assert_issue(fn issue -> assert issue.message =~ "\"pending\" appears 3 times" end)
  end

  test "Mix dependency requirements stay independent, including option tuples" do
    source = ~S"""
    defmodule Sample.MixProject do
      defp deps do
        [{:one, "~> 0.1"}, {:two, "~> 0.1", only: :test}, {:three, "~> 0.1"}]
      end
    end
    """

    source
    |> to_source_file("mix.exs")
    |> run_check(RepeatedLiteral)
    |> refute_issues()

    source
    |> to_source_file("lib/runtime.ex")
    |> run_check(RepeatedLiteral)
    |> assert_issue()
  end

  test "runtime values in Mix dependency options remain checked" do
    ~S"""
    defmodule Sample.MixProject do
      defp app_deps do
        [{:one, git: "https://shared.example/repo"},
         {:two, git: "https://shared.example/repo"},
         {:three, git: "https://shared.example/repo"}]
      end
    end
    """
    |> to_source_file("mix.exs")
    |> run_check(RepeatedLiteral)
    |> assert_issue(fn issue -> assert issue.message =~ "https://shared.example/repo" end)
  end

  test "Ecto lock literals stay literal while query values remain checked" do
    ~S"""
    defmodule Sample do
      import Ecto.Query
      def a, do: from(row in Item, where: row.code == "repeated_value", lock: "FOR UPDATE")
      def b, do: from(row in Item, where: row.code == "repeated_value", lock: "FOR UPDATE")
      def c, do: Ecto.Query.from(row in Item, where: row.code == "repeated_value", lock: "FOR UPDATE")
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(RepeatedLiteral)
    |> assert_issue(fn issue ->
      assert issue.message =~ "repeated_value"
      refute issue.message =~ "FOR UPDATE"
    end)
  end
end
