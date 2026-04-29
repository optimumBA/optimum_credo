defmodule OptimumCredo.Check.Refactor.CaseTrueFalseTest do
  use Credo.Test.Case

  alias OptimumCredo.Check.Refactor.CaseTrueFalse

  test "it should report case with true -> then false -> clauses" do
    """
    defmodule MyModule do
      def process(value) do
        case Map.get(attrs, :active) do
          true -> :yes
          false -> :no
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(CaseTrueFalse)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Replace 'case x do true -> ...; false -> ... end'"
    end)
  end

  test "it should report case with false -> then true -> clauses (reverse order)" do
    """
    defmodule MyModule do
      def process(value) do
        case some_condition do
          false -> :no
          true -> :yes
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(CaseTrueFalse)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Replace 'case x do true -> ...; false -> ... end'"
    end)
  end

  test "it should NOT report case with true, false, and _other wildcard clauses" do
    """
    defmodule MyModule do
      def process(value) do
        case some_condition do
          true -> :yes
          false -> :no
          _other -> :maybe
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(CaseTrueFalse)
    |> refute_issues()
  end

  test "it should NOT report case with non-boolean patterns" do
    """
    defmodule MyModule do
      def process(value) do
        case result do
          {:ok, value} -> value
          {:error, reason} -> raise reason
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(CaseTrueFalse)
    |> refute_issues()
  end

  test "it should NOT report cond expressions (different AST node)" do
    """
    defmodule MyModule do
      def process(x) do
        cond do
          x > 0 -> :positive
          true -> :non_positive
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(CaseTrueFalse)
    |> refute_issues()
  end

  test "it should report the correct line number" do
    """
    defmodule MyModule do
      def process(value) do
        case Map.get(attrs, :active) do
          true -> :yes
          false -> :no
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(CaseTrueFalse)
    |> assert_issue(fn issue ->
      assert issue.line_no == 3
    end)
  end

  test "it should suggest using if in the message" do
    """
    defmodule MyModule do
      def process(value) do
        case Map.get(attrs, :active) do
          true -> :yes
          false -> :no
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(CaseTrueFalse)
    |> assert_issue(fn issue ->
      assert issue.message =~ "'if'"
    end)
  end
end
