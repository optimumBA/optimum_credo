defmodule OptimumCredo.Check.Readability.DepsOrderTest do
  use Credo.Test.Case

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
end
