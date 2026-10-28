defmodule OptimumCredo.Check.Readability.RedundantBooleanComparisonTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.RedundantBooleanComparison

  test "reports boolean-returning expressions compared with true or false" do
    """
    defmodule Sample do
      def run(list, a, b, x) do
        Enum.empty?(list) == true
        Map.has_key?(x, :a) != false
        false === String.valid?(x)
        (a > b) == true
        is_binary(x) == false
        not x == true
        !x == false
        :ok
      end
    end
    """
    |> to_source_file()
    |> run_check(RedundantBooleanComparison)
    |> assert_issues(fn issues -> assert length(issues) == 7 end)
  end

  test "works in guards, pipelines and assertions" do
    """
    defmodule SampleTest do
      def run(x) do
        assert x |> List.first() |> Keyword.has_key?(:a) == true
        if (x == 1) == false, do: :ok
      end
      def guard(x) when is_integer(x) == true, do: x
    end
    """
    |> to_source_file()
    |> run_check(RedundantBooleanComparison)
    |> assert_issues(fn issues -> assert length(issues) == 3 end)
  end

  test "leaves variables and arbitrary calls alone by default" do
    """
    defmodule Sample do
      def run(x, user) do
        x == true
        user.admin == false
        Map.get(user, :admin) != true
        x == nil
        true == true
        x == 1
        :ok
      end
    end
    """
    |> to_source_file()
    |> run_check(RedundantBooleanComparison)
    |> refute_issues()
  end

  test "strict reports variables and arbitrary calls" do
    """
    defmodule Sample do
      def run(x, user) do
        x == true
        Map.get(user, :admin) != false
        x == nil
      end
    end
    """
    |> to_source_file()
    |> run_check(RedundantBooleanComparison, strict: true)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "ignores strings and comments mentioning the pattern" do
    ~S'''
    defmodule Sample do
      # valid?(x) == true
      def run, do: "valid?(x) == true"
    end
    '''
    |> to_source_file()
    |> run_check(RedundantBooleanComparison)
    |> refute_issues()
  end

  test "a ?-suffixed project function is not proof of a boolean result" do
    """
    defmodule Sample do
      def run(x) do
        valid?(x) == true
        Sample.ready?(x) != false
        x |> is_admin() == true
        :ok
      end
    end
    """
    |> to_source_file()
    |> run_check(RedundantBooleanComparison)
    |> refute_issues()
  end

  test "trust_question_mark reports project predicates" do
    """
    defmodule Sample do
      def run(x) do
        valid?(x) == true
        Sample.ready?(x) != false
        x |> is_admin() == true
        x.valid? == true
        :ok
      end
    end
    """
    |> to_source_file()
    |> run_check(RedundantBooleanComparison, trust_question_mark: true)
    |> assert_issues(fn issues -> assert length(issues) == 4 end)
  end

  test "the advice says to negate when the comparison inverts the value" do
    """
    defmodule Sample do
      def run(list) do
        Enum.empty?(list) == false
        Enum.empty?(list) != true
        Enum.empty?(list) == true
        Enum.empty?(list) != false
      end
    end
    """
    |> to_source_file()
    |> run_check(RedundantBooleanComparison)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &(&1.message =~ "negate it with `not`")) == [
               true,
               true,
               false,
               false
             ]
    end)
  end

  test "reports =~, in, Kernel predicates; leaves nil comparisons and unknown calls alone" do
    """
    defmodule Sample do
      def run(a, b, list) do
        (a =~ b) == true
        (a in list) == false
        match?({:ok, _}, a) == true
        function_exported?(Sample, :run, 3) != false
        Kernel.is_nil(a) == true
        a == nil
        Map.get(a, :b?) == true
      end
    end
    """
    |> to_source_file()
    |> run_check(RedundantBooleanComparison)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [3, 4, 5, 6, 7]
    end)
  end
end
