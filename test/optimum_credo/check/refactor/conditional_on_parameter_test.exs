defmodule OptimumCredo.Check.Refactor.ConditionalOnParameterTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Refactor.ConditionalOnParameter

  test "reports a body that is only a case on a parameter" do
    """
    defmodule Sample do
      def label(kind) do
        case kind do
          :admin -> "Admin"
          :member -> "Member"
        end
      end

      defp other(kind, _opts), do: (case kind do
        1 -> :a
        _ -> :b
      end)
    end
    """
    |> to_source_file()
    |> run_check(ConditionalOnParameter)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [3, 9] end)
  end

  test "reports if and unless that test a parameter" do
    """
    defmodule Sample do
      def a(kind), do: if(kind == :admin, do: 1, else: 2)
      def b(value), do: unless(is_nil(value), do: 1, else: 2)
      def c(kinds), do: if(kinds in [:a, :b], do: 1)
    end
    """
    |> to_source_file()
    |> run_check(ConditionalOnParameter)
    |> assert_issues(fn issues -> assert length(issues) == 3 end)
  end

  test "ignores computed subjects, multi-expression bodies, true/false cases and cond" do
    """
    defmodule Sample do
      def a(kind) do
        case lookup(kind) do
          :x -> 1
          _ -> 2
        end
      end

      def b(kind) do
        log(kind)
        case kind do
          :x -> 1
          _ -> 2
        end
      end

      def c(flag) do
        case flag do
          true -> 1
          false -> 2
        end
      end

      def d(kind) do
        cond do
          kind == :a -> 1
          true -> 2
        end
      end

      def e(kind), do: if(other() == kind, do: 1)
      def f(_kind) do
        case _kind do
          :a -> 1
          :b -> 2
        end
      end
      def g(%{kind: kind}) do
        case kind do
          :a -> 1
          :b -> 2
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(ConditionalOnParameter)
    |> refute_issues()
  end

  test "params: min_case_clauses and check_if" do
    source = """
    defmodule Sample do
      def a(kind) do
        case kind do
          :x -> 1
          :y -> 2
        end
      end

      def b(kind), do: if(kind == :a, do: 1)
    end
    """

    source
    |> to_source_file()
    |> run_check(ConditionalOnParameter, min_case_clauses: 3, check_if: false)
    |> refute_issues()

    source
    |> to_source_file()
    |> run_check(ConditionalOnParameter, check_if: false)
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)
  end

  test "ignores conditionals inside strings and comments" do
    ~S'''
    defmodule Sample do
      # def a(x), do: if(x == 1, do: 2)
      def a(_x), do: "if x == 1"
    end
    '''
    |> to_source_file()
    |> run_check(ConditionalOnParameter)
    |> refute_issues()
  end

  test "only plain parameters of the same clause count; computed or nested values do not" do
    """
    defmodule Sample do
      def a(%{kind: kind}) do
        case kind do
          :a -> 1
          :b -> 2
        end
      end

      def b(kind) do
        local = kind
        case local do
          :a -> 1
          :b -> 2
        end
      end

      def c(_kind, other) do
        case other do
          :a -> 1
          :b -> 2
        end
      end

      def d(kind, other), do: if(kind == other, do: 1)
      def e(kind \\\\ :a), do: if(kind == :a, do: 1)
    end
    """
    |> to_source_file()
    |> run_check(ConditionalOnParameter)
    |> assert_issue(fn issue ->
      assert issue.line_no == 18
      assert issue.message =~ "`other`"
    end)
  end

  test "messages read naturally and guards in the head are accepted" do
    """
    defmodule Sample do
      def a(kind) when is_atom(kind), do: if(is_nil(kind), do: 1)
      def b(kind), do: unless(kind in [:a, :b], do: 1)
      def c(kind) do
        case kind do
          :a -> 1
          :b -> 2
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(ConditionalOnParameter)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.message) == [
               "Function body is only an `if` on a parameter; consider separate clauses or guards.",
               "Function body is only an `unless` on a parameter; consider separate clauses or guards.",
               "Function body is only a `case` on `kind`; consider separate clauses or guards."
             ]
    end)
  end
end
