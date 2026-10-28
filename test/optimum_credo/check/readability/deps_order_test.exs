defmodule OptimumCredo.Check.Readability.DepsOrderTest do
  use Credo.Test.Case, async: true

  alias Credo.CLI.Output.Formatter.JSON
  alias OptimumCredo.Check.Readability.DepsOrder

  test "it should NOT report properly ordered dependencies in app_deps" do
    """
    defmodule CredoSampleModule do
      defp app_deps do
        [
          {:apple, "~> 1.0"},
          {:banana, "~> 2.0"},
          {:cherry, "~> 3.0"}
        ]
      end
    end
    """
    |> to_source_file()
    |> run_check(DepsOrder)
    |> refute_issues()
  end

  test "it should NOT report properly ordered dependencies in optimum_deps" do
    """
    defmodule CredoSampleModule do
      defp optimum_deps do
        [
          {:alpha, "~> 1.0"},
          {:beta, "~> 2.0"},
          {:gamma, "~> 3.0"}
        ]
      end
    end
    """
    |> to_source_file()
    |> run_check(DepsOrder)
    |> refute_issues()
  end

  test "it should report dependencies that are out of order in app_deps" do
    """
    defmodule CredoSampleModule do
      defp app_deps do
        [
          {:cherry, "~> 3.0"},
          {:apple, "~> 1.0"},
          {:banana, "~> 2.0"}
        ]
      end
    end
    """
    |> to_source_file()
    |> run_check(DepsOrder)
    |> assert_issue()
  end

  test "it should report dependencies that are out of order in optimum_deps" do
    """
    defmodule CredoSampleModule do
      defp optimum_deps do
        [
          {:gamma, "~> 3.0"},
          {:alpha, "~> 1.0"},
          {:beta, "~> 2.0"}
        ]
      end
    end
    """
    |> to_source_file()
    |> run_check(DepsOrder)
    |> assert_issue()
  end

  test "it should NOT report ordered dependencies with mixed case (case insensitive)" do
    """
    defmodule CredoSampleModule do
      defp app_deps do
        [
          {:apple, "~> 1.0"},
          {:Zebra, "~> 1.0"}
        ]
      end
    end
    """
    |> to_source_file()
    |> run_check(DepsOrder)
    |> refute_issues()
  end

  test "it should report unordered dependencies with mixed case (case insensitive)" do
    """
    defmodule CredoSampleModule do
      defp app_deps do
        [
          {:Zebra, "~> 1.0"},
          {:apple, "~> 1.0"}
        ]
      end
    end
    """
    |> to_source_file()
    |> run_check(DepsOrder)
    |> assert_issue()
  end

  test "it should handle different dependency formats" do
    """
    defmodule CredoSampleModule do
      defp app_deps do
        [
          {:delta, "~> 4.0", override: true},
          {:alpha, "~> 1.0"}
        ]
      end
    end
    """
    |> to_source_file()
    |> run_check(DepsOrder)
    |> assert_issue()
  end

  test "it should NOT report properly ordered complex dependency formats" do
    """
    defmodule CredoSampleModule do
      defp app_deps do
        [
          {:alpha, "~> 1.0"},
          {:delta, "~> 4.0", override: true}
        ]
      end
    end
    """
    |> to_source_file()
    |> run_check(DepsOrder)
    |> refute_issues()
  end

  test "finds the source line of two-element tuples that carry no line metadata" do
    """
    defmodule CredoSampleModule do
      defp app_deps do
        [
          {:cherry, "~> 3.0"},
          {:apple, "~> 1.0"}
        ]
      end
    end
    """
    |> to_source_file()
    |> run_check(DepsOrder)
    |> assert_issue(fn issue ->
      assert issue.message =~ "apple"
      assert issue.line_no == 5
    end)
  end

  test "reports the source line of a two-element dependency tuple" do
    """
    defmodule CredoSampleModule do
      defp app_deps do
        [
          {:apple, "~> 1.0", only: :test},
          {:cherry, "~> 3.0"},
          {:banana, "~> 2.0"}
        ]
      end
    end
    """
    |> to_source_file()
    |> run_check(DepsOrder)
    |> assert_issue(fn issue ->
      assert issue.message =~ "banana"
      assert issue.line_no == 6
    end)
  end

  test "points at the misplaced dependency across comments, not its predecessor" do
    """
    defmodule CredoSampleModule do
      defp app_deps do
        [
          {:ash, "~> 1.0"},
          {:pgvector, "~> 0.3"},
          # sorted below
          {:decimal, "~> 2.0"},
          {:req, "~> 0.5"}
        ]
      end
    end
    """
    |> to_source_file()
    |> run_check(DepsOrder)
    |> assert_issue(fn issue ->
      assert issue.message =~ "decimal"
      refute issue.message =~ "pgvector"
      assert issue.line_no == 7
    end)
  end

  test "reports only the misplaced three-element tuple, with its own line" do
    """
    defmodule CredoSampleModule do
      defp app_deps do
        [
          {:b, "~> 1.0", only: :test},
          {:a, "~> 1.0", only: :test}
        ]
      end
    end
    """
    |> to_source_file()
    |> run_check(DepsOrder)
    |> assert_issue(fn issue ->
      assert issue.message =~ "dependency a "
      assert issue.line_no == 5
    end)
  end

  test "unordered dependency diagnostics can be rendered by Credo JSON" do
    """
    defmodule Sample.MixProject do
      defp app_deps do
        [{:zebra, "~> 1.0"}, {:apple, "~> 1.0"}]
      end
    end
    """
    |> to_source_file()
    |> run_check(DepsOrder)
    |> assert_issue(fn issue ->
      assert issue.trigger == "apple"
      assert %{"trigger" => "apple"} = JSON.issue_to_json(issue)
    end)
  end
end
