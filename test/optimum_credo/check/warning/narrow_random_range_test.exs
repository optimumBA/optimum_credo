defmodule OptimumCredo.Check.Warning.NarrowRandomRangeTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.NarrowRandomRange

  @file_name "test/my_app/thing_test.exs"

  defp run(code, params \\ [], file \\ @file_name) do
    code
    |> to_source_file(file)
    |> run_check(NarrowRandomRange, params)
  end

  test "reports small literal random ranges" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        Enum.random(1..100)
        :rand.uniform(1000)
        Faker.random_between(1, 50)
        random_between(0, 9)
        Enum.random(100..1)
      end
    end
    """
    |> run()
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [4, 5, 6, 7, 8]
    end)
  end

  test "accepts large ranges, dynamic bounds, other functions, strings and quotes" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        Enum.random(1..10_000_000)
        :rand.uniform(1_000_000)
        Faker.random_between(1, n)
        Enum.random(list)
        Enum.random(a..b)
        Other.random(1..5)
        "Enum.random(1..5)"
        quote do
          Enum.random(1..5)
        end
        System.unique_integer([:positive])
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "min_range param and path scoping" do
    code = """
    defmodule ThingTest do
      test "a", do: Enum.random(1..100)
    end
    """

    code
    |> run()
    |> assert_issue()

    code
    |> run(min_range: 50)
    |> refute_issues()

    code
    |> run([], "lib/a.ex")
    |> refute_issues()
  end

  test "piped, stepped and Range.new forms" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        1..100 |> Enum.random()
        Enum.random(1..100//5)
        Enum.random(Range.new(1, 10))
        100 |> :rand.uniform()
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [4, 5, 6, 7] end)
  end

  test "resolves aliased Enum and ignores another module's random" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      alias Enum, as: E
      alias MyApp.Enum, as: MyEnum
      test "a" do
        E.random(1..10)
        MyEnum.random(1..10)
      end
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 6 end)
  end

  test "large, computed and list-based choices are not reported" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        Enum.random(1..1_000_000)
        Enum.random(1..1_000_000_000)
        Enum.random(1..max)
        Enum.random([:a, :b])
        :rand.uniform()
        :rand.uniform(2_000_000)
        Enum.random(1..100//0)
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "negative bounds count their span" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "a", do: Enum.random(-5..5)
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.message =~ "11 distinct" end)
  end
end
