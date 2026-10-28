defmodule OptimumCredo.Check.Refactor.AdjacentClauseOneLiteralTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Refactor.AdjacentClauseOneLiteral

  test "reports adjacent clauses differing in one literal pair" do
    """
    defmodule Sample do
      def fetch(:users), do: Repo.all(from(r in "users", where: r.kind == :users, order_by: r.name))
      def fetch(:teams), do: Repo.all(from(r in "users", where: r.kind == :teams, order_by: r.name))
    end
    """
    |> to_source_file()
    |> run_check(AdjacentClauseOneLiteral)
    |> assert_issue(fn issue ->
      assert issue.line_no == 3
      assert issue.message =~ "fetch/1"
    end)
  end

  test "reports the same literal pair appearing in head and body" do
    """
    defmodule Sample do
      defp build(name, :a), do: Repo.insert(%Thing{name: name, kind: :a, active: true, extra: 1})
      defp build(name, :b), do: Repo.insert(%Thing{name: name, kind: :b, active: true, extra: 1})
    end
    """
    |> to_source_file()
    |> run_check(AdjacentClauseOneLiteral)
    |> assert_issue()
  end

  test "ignores clauses with two different literal pairs, different variables or structure" do
    """
    defmodule Sample do
      def a(:x), do: Repo.all(from(r in "users", where: r.active, order_by: r.name))
      def a(:y), do: Repo.all(from(r in "teams", where: r.active, order_by: r.name))

      def b(x), do: Repo.all(from(r in "users", where: r.active, order_by: x))
      def b(y), do: Repo.all(from(r in "users", where: r.active, order_by: y))

      def c(:x), do: Repo.all(from(r in "users", where: r.active, order_by: r.name))
      def c(:y), do: Repo.all(from(r in "users", where: r.active, order_by: r.id))
      def c(:z), do: other(:z, :z, :z, :z, :z)

      def d(:x), do: foo(:x, :y, 1, 2, 3)
      def d(:y), do: bar(:y, :y, 1, 2, 3)
    end
    """
    |> to_source_file()
    |> run_check(AdjacentClauseOneLiteral)
    |> refute_issues()
  end

  test "ignores small clauses, non-adjacent clauses and different functions" do
    """
    defmodule Sample do
      def a(:x), do: 1
      def a(:y), do: 2

      def b(:x), do: Repo.all(from(r in "users", where: r.active, order_by: r.name))
      def helper, do: :ok
      def b(:y), do: Repo.all(from(r in "teams", where: r.active, order_by: r.name))

      def c(:x), do: Repo.all(from(r in "users", where: r.active, order_by: r.name))
      def d(:y), do: Repo.all(from(r in "teams", where: r.active, order_by: r.name))
    end
    """
    |> to_source_file()
    |> run_check(AdjacentClauseOneLiteral)
    |> refute_issues()
  end

  test "min_nodes param" do
    source = """
    defmodule Sample do
      def a(:x), do: foo(:x)
      def a(:y), do: foo(:y)
    end
    """

    source
    |> to_source_file()
    |> run_check(AdjacentClauseOneLiteral)
    |> refute_issues()

    source
    |> to_source_file()
    |> run_check(AdjacentClauseOneLiteral, min_nodes: 1)
    |> assert_issue()
  end

  test "the documented example is reported, and differing function names or kinds are not" do
    """
    defmodule Sample do
      def sort(:name), do: Repo.all(from(u in User, where: u.active, order_by: field(u, :name)))
      def sort(:email), do: Repo.all(from(u in User, where: u.active, order_by: field(u, :email)))

      def fetch(:users), do: Repo.all(from(u in User, where: u.active, order_by: u.name))
      def fetch(:teams), do: Repo.all(from(u in Team, where: u.active, order_by: u.name))

      def pick(:a), do: Repo.all(from(u in User, where: u.active, order_by: u.name))
      defp pick(:b), do: Repo.all(from(u in User, where: u.active, order_by: u.name))

      def other(:a), do: Repo.all(from(u in User, where: u.active, order_by: u.name))
      def other(:b, 1), do: Repo.all(from(u in User, where: u.active, order_by: u.name))
    end
    """
    |> to_source_file()
    |> run_check(AdjacentClauseOneLiteral)
    |> assert_issue(fn issue ->
      assert issue.line_no == 3
      assert issue.message =~ "sort/1"
    end)
  end

  test "clauses separated by another definition are not adjacent, and min_nodes applies" do
    """
    defmodule Sample do
      def go(:a), do: Repo.all(from(u in User, where: u.active, order_by: u.name))
      def other, do: :ok
      def go(:b), do: Repo.all(from(u in User, where: u.active, order_by: u.name))

      def tiny(:a), do: foo(:a)
      def tiny(:b), do: foo(:b)
    end
    """
    |> to_source_file()
    |> run_check(AdjacentClauseOneLiteral)
    |> refute_issues()
  end

  test "does not report literals that differ only in head patterns" do
    """
    defmodule Sample do
      defp pick(<<"Alpha ", _rest::binary>>, item, map) do
        entry = map[:one]
        store(item, entry)
      end

      defp pick(<<"Beta", _rest::binary>>, item, map) do
        entry = map[:one]
        store(item, entry)
      end

      def route(:get, conn), do: Repo.all(from(u in User, where: u.active, order_by: u.name))
      def route(:head, conn), do: Repo.all(from(u in User, where: u.active, order_by: u.name))
    end
    """
    |> to_source_file()
    |> run_check(AdjacentClauseOneLiteral, min_nodes: 1)
    |> refute_issues()
  end
end
