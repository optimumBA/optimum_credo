defmodule OptimumCredo.Check.Readability.ImplementationHelperInAssertionTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.ImplementationHelperInAssertion

  @file_name "test/my_app/money_test.exs"

  defp run(code, params \\ [], file \\ @file_name) do
    code
    |> to_source_file(file)
    |> run_check(ImplementationHelperInAssertion, params)
  end

  test "reports expectation built with the module under test" do
    """
    defmodule MyApp.MoneyTest do
      use ExUnit.Case
      test "renders" do
        assert html =~ MyApp.Money.format(price)
        assert MyApp.Money.format(a) == MyApp.Money.format(b)
        refute html =~ MyApp.Money.humanize(price)
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert length(issues) == 3 end)
  end

  test "recognises a short alias only when declared" do
    code = """
    defmodule MyApp.MoneyTest do
      use ExUnit.Case
      alias MyApp.Money
      test "renders" do
        assert html =~ Money.format(price)
      end
    end
    """

    code
    |> run()
    |> assert_issue()

    code
    |> String.replace("  alias MyApp.Money\n", "")
    |> run()
    |> refute_issues()
  end

  test "accepts hardcoded expectations and the helper on the left-hand side" do
    """
    defmodule MyApp.MoneyTest do
      use ExUnit.Case
      test "renders" do
        assert MyApp.Money.format(price) == "$5.00"
        assert html =~ "$5.00"
        assert html =~ "MyApp.Money.format(price)"
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "ignores other modules, non-formatting functions and quoted code" do
    """
    defmodule MyApp.MoneyTest do
      use ExUnit.Case
      test "renders" do
        assert html =~ Other.Money.format(price)
        assert MyApp.Money.cents(a) == MyApp.Money.cents(b)
        quote do
          assert html =~ MyApp.Money.format(price)
        end
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "modules and helper_pattern params" do
    code = """
    defmodule MyApp.MoneyTest do
      use ExUnit.Case
      test "renders" do
        assert html =~ MyApp.Formatter.pretty(price)
        assert html =~ MyApp.Money.cents(price)
      end
    end
    """

    code
    |> run()
    |> refute_issues()

    code
    |> run(modules: [MyApp.Formatter], helper_pattern: "^pretty")
    |> assert_issue()

    code
    |> run(helper_pattern: "^cents")
    |> assert_issue()

    code
    |> run([helper_pattern: "^cents"], "lib/x.ex")
    |> refute_issues()
  end

  test "LiveView test names map to the live module" do
    """
    defmodule MyAppWeb.ThingLiveTest do
      use ExUnit.Case
      test "x" do
        assert html =~ MyAppWeb.ThingLive.format_title(t)
      end
    end
    """
    |> run()
    |> assert_issue()
  end

  test "a literal on the left makes the right-hand helper the function under test" do
    """
    defmodule MyApp.MoneyTest do
      use ExUnit.Case
      test "renders" do
        assert "$5.00" == MyApp.Money.format(500)
        assert 5 == MyApp.Money.to_dollars(500)
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "follows a variable assigned from the helper into the assertion" do
    """
    defmodule MyApp.MoneyTest do
      use ExUnit.Case
      test "renders" do
        expected = MyApp.Money.format(500)
        assert render(view) =~ expected
      end
      test "tests the helper directly" do
        formatted = MyApp.Money.format(500)
        assert formatted == "$5.00"
      end
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 5 end)
  end

  test "resolves aliases with as:, grouped aliases and imports" do
    """
    defmodule MyApp.MoneyTest do
      use ExUnit.Case
      alias MyApp.Money, as: M
      alias MyApp.{Money}
      import MyApp.Money, only: [format: 1]

      test "renders" do
        assert html =~ M.format(1)
        assert html =~ Money.format(1)
        assert html =~ format(1)
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [8, 9, 10] end)
  end

  test "another module of the same application is watched, fixtures are not" do
    code = """
    defmodule MyAppWeb.PageLiveTest do
      use ExUnit.Case
      alias MyApp.Formatter
      alias MyApp.Fixtures

      test "renders" do
        assert html =~ Formatter.format_price(5)
        assert html =~ Fixtures.display_name(5)
        assert html =~ Jason.encode!(5)
        assert html =~ Date.to_string(5)
      end
    end
    """

    code
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 7 end)

    code
    |> run(watch_namespace: false)
    |> refute_issues()
  end

  test "an alias to another module with the same short name is not the module under test" do
    """
    defmodule MyApp.MoneyTest do
      use ExUnit.Case
      alias Other.Money
      test "renders" do
        assert html =~ Money.format(1)
      end
    end
    """
    |> run(watch_namespace: false)
    |> refute_issues()
  end

  test "!= and !== are comparisons too" do
    """
    defmodule MyApp.MoneyTest do
      use ExUnit.Case
      test "renders" do
        assert html != MyApp.Money.format(1)
        refute html !== MyApp.Money.format(1)
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "a variable assigned from the helper is the actual value when it is on the left" do
    """
    defmodule MyApp.CardWriterTest do
      use ExUnit.Case
      test "renders" do
        card = MyApp.CardWriter.render(finding)
        assert card =~ "---"
        assert card =~ ~r/^id: B-999$/m
        assert card == other_card
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "variables from a namespace-only module are actual values, not expectations" do
    """
    defmodule MyApp.PageTest do
      use ExUnit.Case
      alias MyApp.Driver
      test "compares two renders" do
        before_html = Driver.render_html(session)
        after_html = Driver.render_html(session2)
        assert before_html == after_html
      end
    end
    """
    |> run()
    |> refute_issues()
  end
end
