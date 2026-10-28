defmodule OptimumCredo.Check.Warning.HardcodedYearInTestTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.HardcodedYearInTest

  @file_name "test/my_app/thing_test.exs"

  defp run(code, params \\ [], file \\ @file_name) do
    code
    |> to_source_file(file)
    |> run_check(HardcodedYearInTest, params)
  end

  test "reports sigils, ISO strings, Date.new and year keywords with line numbers" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        a = ~D[2025-01-31]
        b = Date.new!(2026, 1, 1)
        c = Date.from_iso8601!("2027-05-06")
        d = %{year: 2028, month: 1}
        e = ~U[2029-01-01 00:00:00Z]
      end
    end
    """
    |> run()
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [4, 5, 6, 7, 8]
    end)
  end

  test "ignores derived dates, unrelated integers, out-of-range years and quoted code" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        Date.add(Date.utc_today(), 30)
        assert total == 2025
        Money.new(2025)
        Date.new!(1990, 1, 1)
        "year 2025 was fine"
        "2025-1-1"
        ~T[10:00:00]
        quote do
          ~D[2025-01-01]
        end
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "min_year, max_year and allow_years params" do
    code = """
    defmodule ThingTest do
      test "a", do: ~D[2025-01-31]
    end
    """

    code
    |> run()
    |> assert_issue()

    code
    |> run(min_year: 2026)
    |> refute_issues()

    code
    |> run(max_year: 2024)
    |> refute_issues()

    code
    |> run(allow_years: [2025])
    |> refute_issues()
  end

  test "ignores non-test files" do
    "defmodule A do\n def a, do: ~D[2025-01-31]\nend"
    |> run([], "lib/a.ex")
    |> refute_issues()
  end

  test "unrelated numeric literals are never reported" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        price = 2024
        book = %{title: "x", year: 2021}
        port = 2050
        assert Enum.count(list) == 2025
        Process.sleep(2030)
        Money.new(2026, :usd)
        Repo.insert!(%Order{total: 2022, count: 2023})
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "year keys count only next to month or day, in maps, structs and keywords" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        a = %Date{year: 2025, month: 1, day: 3}
        b = %{year: 2026,
              day: 2}
        c = [year: 2027, month: 4]
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [4, 5, 7] end)
  end

  test "reports the literal's own line in multi-line lists and maps" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        dates = [
          "2025-01-01",
          "not a date",

          "2025-02-02T10:00:00Z"
        ]
        build(
          name: "x",
          inserted_at: ~N[2026-03-04 00:00:00]
        )
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [5, 8, 12] end)
  end

  test "invalid dates, prose and docs are ignored; interpolated date prefixes are reported" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      @moduledoc "Covers 2025-01-01"
      test "a" do
        build(code: "2025-13-45", id: "2025-01-001-9999", note: "see 2025-01-31")
        iso = "2025-01-\#{day}"
      end
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 6 end)
  end

  test "resolves aliases and from_erl tuples" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      alias NaiveDateTime, as: N
      alias MyApp.Date
      test "a" do
        N.new!(2025, 1, 1, 0, 0, 0)
        Date.new(2025, 1, 1)
        Date.from_erl!({2026, 5, 6})
        NaiveDateTime.from_erl!({{2027, 5, 6}, {0, 0, 0}})
        :calendar.date_to_gregorian_days({2028, 1, 1})
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [6, 9] end)
  end
end
