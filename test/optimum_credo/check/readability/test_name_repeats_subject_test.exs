defmodule OptimumCredo.Check.Readability.TestNameRepeatsSubjectTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.TestNameRepeatsSubject

  @file_name "test/my_app/lines_test.exs"

  defp run(code, params \\ [], file \\ @file_name) do
    code
    |> to_source_file(file)
    |> run_check(TestNameRepeatsSubject, params)
  end

  test "reports test names repeating the described function" do
    """
    defmodule LinesTest do
      describe "calc_lines/1" do
        test "calc_lines/1 returns zero", do: :ok
        test "calc_lines handles blanks", do: :ok
        test "returns zero for nil", do: :ok
      end
    end
    """
    |> run()
    |> assert_issues(fn issues ->
      assert length(issues) == 2
      assert Enum.all?(issues, &(&1.message =~ "calc_lines"))
    end)
  end

  test "supports ? and ! function names" do
    """
    defmodule LinesTest do
      describe "valid_line?/1" do
        test "valid_line? is true for blanks", do: :ok
      end
    end
    """
    |> run()
    |> assert_issue()
  end

  test "does not match longer identifiers or another describe's name" do
    """
    defmodule LinesTest do
      describe "calc_lines/1" do
        test "calc_lines_total is separate", do: :ok
        test "precalc_lines works", do: :ok
      end
      describe "other_fn/1" do
        test "calc_lines is mentioned elsewhere", do: :ok
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "skips non-arity describes, short names and interpolated names" do
    """
    defmodule LinesTest do
      describe "when signed in" do
        test "when signed in works", do: :ok
      end
      describe "get/1" do
        test "get returns a thing", do: :ok
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "min_subject_length param and path scoping" do
    code = """
    defmodule LinesTest do
      describe "get/1" do
        test "get returns a thing", do: :ok
      end
    end
    """

    code
    |> run(min_subject_length: 3)
    |> assert_issue()

    code
    |> run([min_subject_length: 3], "test/support/x_test.exs")
    |> refute_issues()

    code
    |> run([min_subject_length: 3], "lib/x.ex")
    |> refute_issues()
  end

  test "reports only whole-word matches, with ? and ! suffixes" do
    """
    defmodule LinesTest do
      describe "valid_line?/1" do
        test "valid_line? is true", do: :ok
        test "valid_lines are listed", do: :ok
        test "is not valid_line_count", do: :ok
      end
      describe "save!/1" do
        test "save! raises", do: :ok
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [3, 8] end)
  end

  test "interpolated and variable test names do not crash and contribute their literal text" do
    """
    defmodule LinesTest do
      describe "calc_lines/1" do
        test "calc_lines \#{x}", do: :ok
        test "\#{x} fine", do: :ok
        test @name, do: :ok
      end
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)
  end

  test "ignores non-arity describes and quoted tests" do
    """
    defmodule LinesTest do
      describe "when empty" do
        test "when empty returns zero", do: :ok
      end
      defmacro shared do
        quote do
          describe "calc_lines/1" do
            test "calc_lines/1 returns", do: :ok
          end
        end
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "a plain-word subject is only matched at the start or as code" do
    """
    defmodule LinesTest do
      describe "enqueue/1" do
        test "does not enqueue a job", do: :ok
        test "returns the index of the job", do: :ok
        test "enqueue fails for blanks", do: :ok
        test "calls enqueue/1 twice", do: :ok
        test "uses `enqueue` once", do: :ok
      end
    end
    """
    |> run()
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [5, 6, 7]
    end)
  end
end
