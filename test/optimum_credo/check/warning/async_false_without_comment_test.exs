defmodule OptimumCredo.Check.Warning.AsyncFalseWithoutCommentTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.AsyncFalseWithoutComment

  @file_name "test/my_app/thing_test.exs"

  defp run(code, params \\ [], file \\ @file_name) do
    code
    |> to_source_file(file)
    |> run_check(AsyncFalseWithoutComment, params)
  end

  test "reports async: false without a comment" do
    """
    defmodule ThingTest do
      use MyApp.DataCase, async: false
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 2 end)
  end

  test "accepts a comment on the preceding line or the same line" do
    """
    defmodule AThingTest do
      # Mutates global application env
      use ExUnit.Case, async: false
    end

    defmodule BThingTest do
      use ExUnit.Case, async: false # global registry
    end
    """
    |> run()
    |> refute_issues()
  end

  test "a trailing comment of earlier code does not count" do
    """
    defmodule ThingTest do
      @x 1 # unrelated
      use ExUnit.Case, async: false
    end
    """
    |> run()
    |> assert_issue()
  end

  test "ignores async: true, missing option, non-Case modules and strings" do
    """
    defmodule ThingTest do
      use ExUnit.Case, async: true
      use MyApp.ConnCase
      use Something, async: false
      @doc "use ExUnit.Case, async: false"
    end
    """
    |> run()
    |> refute_issues()
  end

  test "require_comment false reports even commented modules" do
    """
    defmodule ThingTest do
      # reason
      use ExUnit.Case, async: false
    end
    """
    |> run(require_comment: false)
    |> assert_issue()
  end

  test "case_suffix and moduletag exemption" do
    code = """
    defmodule ThingTest do
      use MyApp.Harness, async: false
    end
    """

    code
    |> run()
    |> refute_issues()

    code
    |> run(case_suffix: "Harness")
    |> assert_issue()

    """
    defmodule ThingTest do
      @moduletag :timing
      use ExUnit.Case, async: false
    end
    """
    |> run()
    |> refute_issues()
  end

  test "ignores non-test files" do
    """
    defmodule Thing do
      use ExUnit.Case, async: false
    end
    """
    |> run([], "lib/thing.ex")
    |> refute_issues()
  end

  test "resolves an aliased case module" do
    """
    defmodule ThingTest do
      alias MyApp.DataCase, as: Base
      use Base, async: false
    end
    """
    |> run()
    |> assert_issue()
  end

  test "an alias to a non-case module hides a Case-looking name" do
    """
    defmodule ThingTest do
      alias MyApp.Helper, as: DataCase
      use DataCase, async: false
    end
    """
    |> run()
    |> refute_issues()
  end

  test "a blank line between the comment and the use does not count as preceding" do
    """
    defmodule ThingTest do
      # explains something else

      use ExUnit.Case, async: false
    end
    """
    |> run()
    |> assert_issue()
  end

  test "ignores use inside quote and async: true" do
    """
    defmodule MyApp.CaseTemplate do
      defmacro __using__(_) do
        quote do
          use ExUnit.Case, async: false
        end
      end
    end

    defmodule ThingTest do
      use ExUnit.Case, async: true
    end
    """
    |> run()
    |> refute_issues()
  end
end
