defmodule OptimumCredo.Check.Warning.SeedInsertWithoutOnConflictTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.SeedInsertWithoutOnConflict

  defp run(source, params \\ [], path \\ "priv/repo/seeds.exs") do
    source
    |> to_source_file(path)
    |> run_check(SeedInsertWithoutOnConflict, params)
  end

  test "it reports insert, insert! and insert_all without on_conflict" do
    """
    alias MyApp.Repo

    Repo.insert!(%Role{name: "admin"})
    Repo.insert(%Role{name: "user"})
    Repo.insert_all(Role, [%{name: "guest"}])
    MyApp.Repo.insert!(%Role{name: "root"}, returning: true)
    """
    |> run()
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [3, 4, 5, 6]

      assert Enum.map(issues, & &1.trigger) == [
               "Repo.insert!",
               "Repo.insert",
               "Repo.insert_all",
               "Repo.insert!"
             ]
    end)
  end

  test "it reports piped inserts and inserts inside loops" do
    """
    %Role{name: "admin"} |> Repo.insert!()

    for name <- ["a", "b"] do
      Repo.insert!(%Role{name: name})
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "it treats on_conflict: :raise as missing" do
    ~s|Repo.insert!(%Role{}, on_conflict: :raise)|
    |> run()
    |> assert_issue()
  end

  test "it accepts any other on_conflict strategy" do
    """
    Repo.insert!(%Role{}, on_conflict: :nothing)
    Repo.insert!(%Role{}, on_conflict: {:replace, [:name]}, conflict_target: :id)
    Repo.insert!(%Role{}, on_conflict: [set: [name: "x"]])
    Repo.insert_all(Role, rows, on_conflict: :replace_all, conflict_target: :id)
    %Role{} |> Repo.insert!(on_conflict: :nothing)
    """
    |> run()
    |> refute_issues()
  end

  test "it cannot see options passed as a variable" do
    "Repo.insert!(%Role{}, opts)\nRepo.insert_all(Role, rows, opts)"
    |> run()
    |> refute_issues()
  end

  test "it accepts inserts guarded by a lookup" do
    """
    Repo.get_by(Role, name: "admin") || Repo.insert!(%Role{name: "admin"})

    unless Repo.exists?(Role) do
      Repo.insert!(%Role{name: "first"})
    end

    case Repo.get(Role, 1) do
      nil -> Repo.insert!(%Role{id: 1})
      role -> role
    end

    Repo.one(Role) |> case do
      nil -> Repo.insert!(%Role{})
      role -> role
    end

    with nil <- Repo.get(Role, 2), {:ok, role} <- Repo.insert(%Role{id: 2}) do
      role
    end
    """
    |> run()
    |> refute_issues()
  end

  test "an unrelated lookup before the insert does not guard it" do
    """
    Repo.all(Role)
    Repo.insert!(%Role{name: "admin"})
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 2 end)
  end

  test "it ignores non-Repo receivers, other Repo functions, strings and comments" do
    """
    Cache.insert(%Role{})
    Repo.update!(changeset)
    Repo.delete_all(Role)
    # Repo.insert!(%Role{})
    IO.puts("Repo.insert!(%Role{})")
    """
    |> run()
    |> refute_issues()
  end

  test "it applies to seed directories and honours seed_paths" do
    source = "Repo.insert!(%Role{})"

    source
    |> run([], "priv/repo/seeds/roles.exs")
    |> assert_issue()

    source
    |> run([], "lib/my_app/roles.ex")
    |> refute_issues()

    source
    |> run([], "priv/repo/migrations/20260101_a.exs")
    |> refute_issues()

    source
    |> run([], "priv/repo/seeds.exs.bak")
    |> refute_issues()

    source
    |> run([seed_paths: ["priv/seeds/"]], "priv/repo/seeds.exs")
    |> refute_issues()

    source
    |> run([seed_paths: ["priv/seeds/"]], "priv/seeds/dev.exs")
    |> assert_issue()
  end

  describe "review regressions" do
    test "piped inserts count their options correctly" do
      """
      %Role{name: "a"} |> Repo.insert!()
      %Role{name: "b"} |> Repo.insert!(on_conflict: :nothing)
      %Role{name: "c"} |> Repo.insert!(opts)
      %Role{name: "d"} |> Repo.insert!(on_conflict: :raise)
      """
      |> run()
      |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [1, 4] end)
    end

    test "it follows an alias of the repo" do
      """
      alias MyApp.Repo, as: R
      R.insert!(%Role{name: "a"})
      """
      |> run()
      |> assert_issue(fn issue -> assert issue.line_no == 2 end)
    end

    test "a module aliased as Repo that is not a repo is not read" do
      """
      alias MyApp.Cache, as: Repo
      Repo.insert!(%Role{name: "a"})
      """
      |> run()
      |> refute_issues()
    end

    test "other insert-like calls and non-seed files are ignored" do
      "Cache.insert(:key, 1)\nEnum.each(rows, &Map.put(&1, :a, 1))"
      |> run()
      |> refute_issues()

      "Repo.insert!(%Role{})"
      |> run([], "lib/my_app/accounts.ex")
      |> refute_issues()
    end
  end
end
