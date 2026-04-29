defmodule OptimumCredo.Check.Warning.SkippedTestTest do
  use Credo.Test.Case

  alias OptimumCredo.Check.Warning.SkippedTest

  test "it should report @tag :skip" do
    """
    defmodule MyTest do
      use ExUnit.Case

      @tag :skip
      test "something" do
        assert 1 == 1
      end
    end
    """
    |> to_source_file()
    |> run_check(SkippedTest)
    |> assert_issue(fn issue ->
      assert issue.message =~ "@tag :skip"
    end)
  end

  test "it should report @tag skip: true (keyword list form)" do
    """
    defmodule MyTest do
      use ExUnit.Case

      @tag skip: true
      test "something" do
        assert 1 == 1
      end
    end
    """
    |> to_source_file()
    |> run_check(SkippedTest)
    |> assert_issue(fn issue ->
      assert issue.message =~ "@tag :skip"
    end)
  end

  test "it should report @tag skip: \"reason\" (string value form)" do
    """
    defmodule MyTest do
      use ExUnit.Case

      @tag skip: "waiting on issue #123"
      test "something" do
        assert 1 == 1
      end
    end
    """
    |> to_source_file()
    |> run_check(SkippedTest)
    |> assert_issue(fn issue ->
      assert issue.message =~ "@tag :skip"
    end)
  end

  test "it should report @moduletag :skip" do
    """
    defmodule MyTest do
      use ExUnit.Case

      @moduletag :skip

      test "something" do
        assert 1 == 1
      end
    end
    """
    |> to_source_file()
    |> run_check(SkippedTest)
    |> assert_issue(fn issue ->
      assert issue.message =~ "@moduletag :skip"
    end)
  end

  test "it should report @moduletag skip: true (keyword list form)" do
    """
    defmodule MyTest do
      use ExUnit.Case

      @moduletag skip: true

      test "something" do
        assert 1 == 1
      end
    end
    """
    |> to_source_file()
    |> run_check(SkippedTest)
    |> assert_issue(fn issue ->
      assert issue.message =~ "@moduletag :skip"
    end)
  end

  test "it should NOT report @tag :async" do
    """
    defmodule MyTest do
      use ExUnit.Case, async: true

      @tag :async
      test "something" do
        assert 1 == 1
      end
    end
    """
    |> to_source_file()
    |> run_check(SkippedTest)
    |> refute_issues()
  end

  test "it should NOT report @tag capture_log: true" do
    """
    defmodule MyTest do
      use ExUnit.Case

      @tag capture_log: true
      test "something" do
        assert 1 == 1
      end
    end
    """
    |> to_source_file()
    |> run_check(SkippedTest)
    |> refute_issues()
  end

  test "it should still report @tag :skip # comment when allow_with_comment is false (default)" do
    """
    defmodule MyTest do
      use ExUnit.Case

      @tag :skip # waiting on issue #123
      test "something" do
        assert 1 == 1
      end
    end
    """
    |> to_source_file()
    |> run_check(SkippedTest)
    |> assert_issue(fn issue ->
      assert issue.message =~ "@tag :skip"
    end)
  end

  test "it should NOT report @tag :skip # comment when allow_with_comment: true" do
    """
    defmodule MyTest do
      use ExUnit.Case

      @tag :skip # waiting on issue #123
      test "something" do
        assert 1 == 1
      end
    end
    """
    |> to_source_file()
    |> run_check(SkippedTest, allow_with_comment: true)
    |> refute_issues()
  end

  test "it should report @tag :skip with no comment even when allow_with_comment: true" do
    """
    defmodule MyTest do
      use ExUnit.Case

      @tag :skip
      test "something" do
        assert 1 == 1
      end
    end
    """
    |> to_source_file()
    |> run_check(SkippedTest, allow_with_comment: true)
    |> assert_issue(fn issue ->
      assert issue.message =~ "@tag :skip"
    end)
  end

  test "it should report the correct line number" do
    """
    defmodule MyTest do
      use ExUnit.Case

      @tag :skip
      test "something" do
        assert 1 == 1
      end
    end
    """
    |> to_source_file()
    |> run_check(SkippedTest)
    |> assert_issue(fn issue ->
      assert issue.line_no == 4
    end)
  end
end
