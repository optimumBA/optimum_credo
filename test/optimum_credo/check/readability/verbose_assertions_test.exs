defmodule OptimumCredo.Check.Readability.VerboseAssertionsTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.VerboseAssertions

  test "it should NOT report idiomatic assertions" do
    """
    defmodule MyTest do
      test "idiomatic assertions" do
        assert user.id
        refute user.name
        assert status
        refute error
      end
    end
    """
    |> to_source_file()
    |> run_check(VerboseAssertions)
    |> refute_issues()
  end

  test "it should report verbose assert with != nil" do
    """
    defmodule MyTest do
      test "verbose assertion" do
        assert drop.id != nil
      end
    end
    """
    |> to_source_file()
    |> run_check(VerboseAssertions)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Use `refute is_nil(drop.id)` instead of verbose nil comparison"
    end)
  end

  test "it should report verbose assert with == nil" do
    """
    defmodule MyTest do
      test "verbose assertion" do
        assert user.name == nil
      end
    end
    """
    |> to_source_file()
    |> run_check(VerboseAssertions)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Use `assert is_nil(user.name)` instead of verbose nil comparison"
    end)
  end

  test "it should report verbose refute with != nil" do
    """
    defmodule MyTest do
      test "verbose refute" do
        refute item.id != nil
      end
    end
    """
    |> to_source_file()
    |> run_check(VerboseAssertions)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Use `assert is_nil(item.id)` instead of verbose nil comparison"
    end)
  end

  test "it should report verbose refute with == nil" do
    """
    defmodule MyTest do
      test "verbose refute" do
        refute status == nil
      end
    end
    """
    |> to_source_file()
    |> run_check(VerboseAssertions)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Use `refute is_nil(status)` instead of verbose nil comparison"
    end)
  end

  test "it should handle nil on the left side of comparison" do
    """
    defmodule MyTest do
      test "nil on left side" do
        assert nil != result
        assert nil == empty_result
      end
    end
    """
    |> to_source_file()
    |> run_check(VerboseAssertions)
    |> assert_issues(fn issues ->
      assert length(issues) == 2
      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &String.contains?(&1, "refute is_nil(result)"))
      assert Enum.any?(messages, &String.contains?(&1, "assert is_nil(empty_result)"))
    end)
  end

  test "it should handle complex expressions" do
    """
    defmodule MyTest do
      test "complex expressions" do
        assert user.profile.avatar != nil
        assert Map.get(data, :key) == nil
      end
    end
    """
    |> to_source_file()
    |> run_check(VerboseAssertions)
    |> assert_issues(fn issues ->
      assert length(issues) == 2
      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &String.contains?(&1, "refute is_nil(user.profile.avatar)"))
      assert Enum.any?(messages, &String.contains?(&1, "assert is_nil(Map.get(data, :key))"))
    end)
  end

  test "it should NOT report non-nil comparisons" do
    """
    defmodule MyTest do
      test "non-nil comparisons" do
        assert value == :ok
        assert result != :error
        refute status == :failed
        refute count != 0
      end
    end
    """
    |> to_source_file()
    |> run_check(VerboseAssertions)
    |> refute_issues()
  end

  test "it should NOT report is_nil function calls" do
    """
    defmodule MyTest do
      test "is_nil usage" do
        assert is_nil(value)
        refute is_nil(result)
      end
    end
    """
    |> to_source_file()
    |> run_check(VerboseAssertions)
    |> refute_issues()
  end

  test "it should handle multiple verbose assertions in one test" do
    """
    defmodule MyTest do
      test "multiple verbose assertions" do
        assert user.id != nil
        assert user.email != nil
        assert user.profile == nil
        refute user.active != nil
      end
    end
    """
    |> to_source_file()
    |> run_check(VerboseAssertions)
    |> assert_issues(fn issues ->
      assert length(issues) == 4
    end)
  end

  test "it should handle function calls in assertions" do
    """
    defmodule MyTest do
      test "function calls in assertions" do
        assert get_user(id) != nil
        refute find_by_email(email) == nil
      end
    end
    """
    |> to_source_file()
    |> run_check(VerboseAssertions)
    |> assert_issues(fn issues ->
      assert length(issues) == 2
      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &String.contains?(&1, "refute is_nil(get_user(id))"))
      assert Enum.any?(messages, &String.contains?(&1, "refute is_nil(find_by_email(email))"))
    end)
  end

  test "it should handle pipe expressions" do
    """
    defmodule MyTest do
      test "pipe expressions" do
        assert user |> get_profile() != nil
      end
    end
    """
    |> to_source_file()
    |> run_check(VerboseAssertions)
    |> assert_issue(fn issue ->
      assert issue.message =~ "refute is_nil(user |> get_profile())"
    end)
  end

  test "recommendations preserve the meaning of false-valued expressions" do
    """
    defmodule PredicateTest do
      test "false is present" do
        assert value != nil
        refute value == nil
      end
    end
    """
    |> to_source_file()
    |> run_check(VerboseAssertions)
    |> assert_issues(fn issues ->
      assert length(issues) == 2
      assert Enum.all?(issues, &String.contains?(&1.message, "refute is_nil(value)"))
    end)

    value = Enum.at([false], 0)
    assert value != nil
    refute value == nil
    refute is_nil(value)
  end
end
