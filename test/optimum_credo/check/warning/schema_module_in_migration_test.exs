defmodule OptimumCredo.Check.Warning.SchemaModuleInMigrationTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.SchemaModuleInMigration

  @path "priv/repo/migrations/20260101000000_backfill.exs"

  defp run(source, params \\ [], path \\ @path) do
    source
    |> to_source_file(path)
    |> run_check(SchemaModuleInMigration, params)
  end

  test "it reports an alias of an app schema" do
    """
    defmodule MyApp.Repo.Migrations.Backfill do
      use Ecto.Migration

      alias MyApp.Accounts.User

      def up, do: execute("select 1")
    end
    """
    |> run()
    |> assert_issue(fn issue ->
      assert issue.message =~ "MyApp.Accounts.User"
      assert issue.line_no == 4
    end)
  end

  test "it reports remote calls and struct literals" do
    """
    defmodule MyApp.Repo.Migrations.Backfill do
      use Ecto.Migration

      def up do
        MyApp.Repo.insert!(%MyApp.Accounts.User{name: "x"})
        MyApp.Accounts.list_users()
      end
    end
    """
    |> run()
    |> assert_issues(fn issues ->
      assert issues
             |> Enum.map(& &1.trigger)
             |> Enum.sort() == [
               "MyApp.Accounts",
               "MyApp.Accounts.User"
             ]
    end)
  end

  test "it expands multi-alias groups" do
    """
    defmodule MyApp.Repo.Migrations.Backfill do
      alias MyApp.{Accounts.User, Repo}
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Accounts.User" end)
  end

  test "it allows Repo, Ecto, raw table queries and the migration module itself" do
    """
    defmodule MyApp.Repo.Migrations.Backfill do
      use Ecto.Migration
      import Ecto.Query
      alias MyApp.Repo

      def up do
        Repo.update_all(from(u in "users"), set: [active: true])
        MyApp.Repo.query!("select 1")
        _ = MyApp.Repo.Migrations.Other
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "it ignores strings, comments and atoms that look like modules" do
    """
    defmodule MyApp.Repo.Migrations.Backfill do
      # MyApp.Accounts.User was dropped
      def up, do: execute("UPDATE users -- MyApp.Accounts.User") && :"Elixir.MyApp.Accounts.User"
    end
    """
    |> run()
    |> refute_issues()
  end

  test "it only checks migration files" do
    source = """
    defmodule MyApp.Repo.Migrations.Backfill do
      alias MyApp.Accounts.User
    end
    """

    source
    |> run([], "lib/my_app/accounts.ex")
    |> refute_issues()

    source
    |> run([], "priv/repo/seeds.exs")
    |> refute_issues()
  end

  test "it honours app_namespace and does nothing without a known namespace" do
    source = """
    defmodule Repo.Migrations.Backfill do
      alias Acme.Billing.Invoice
    end
    """

    source
    |> run(app_namespace: "Acme")
    |> assert_issue()

    source
    |> run(app_namespace: :Acme)
    |> assert_issue()

    source
    |> run(app_namespace: "Other")
    |> refute_issues()
  end

  test "it honours allowed_modules and ignore_files" do
    source = """
    defmodule MyApp.Repo.Migrations.Backfill do
      alias MyApp.Vault
      alias MyApp.Vault.Key
    end
    """

    source
    |> run(allowed_modules: ["MyApp.Vault"])
    |> refute_issues()

    source
    |> run(ignore_files: ["20260101000000_backfill.exs"])
    |> refute_issues()

    source
    |> run(ignore_files: [~r/20260101/])
    |> refute_issues()

    source
    |> run(ignore_files: ["other.exs"])
    |> assert_issues()
  end

  describe "review regressions" do
    test "it follows a partial alias to the app module" do
      """
      defmodule MyApp.Repo.Migrations.Backfill do
        use Ecto.Migration

        alias MyApp.Accounts

        def up, do: Accounts.User |> repo().all()
      end
      """
      |> run()
      |> assert_issues(fn issues ->
        assert Enum.map(issues, &{&1.line_no, &1.trigger}) ==
                 [{4, "MyApp.Accounts"}, {6, "MyApp.Accounts.User"}]
      end)
    end

    test "it reports a name introduced by an alias once, at the alias" do
      """
      defmodule MyApp.Repo.Migrations.Backfill do
        use Ecto.Migration

        alias MyApp.Accounts.User, as: Person

        def up, do: repo().insert!(%Person{})
      end
      """
      |> run()
      |> assert_issue(fn issue -> assert issue.line_no == 4 end)
    end

    test "an alias does not leak out of the nested module that defines it" do
      """
      defmodule MyApp.Repo.Migrations.Backfill do
        use Ecto.Migration

        defmodule Helper do
          alias MyApp.Accounts
        end

        def up, do: Accounts.User
      end
      """
      |> run()
      |> assert_issue(fn issue -> assert issue.line_no == 5 end)
    end

    test "it ignores comments and strings that mention app modules" do
      """
      defmodule MyApp.Repo.Migrations.Backfill do
        use Ecto.Migration

        # MyApp.Accounts.User used to be here
        @moduledoc "see MyApp.Accounts.User"

        def up, do: execute("UPDATE users SET name = 'MyApp.Accounts.User'")
      end
      """
      |> run()
      |> refute_issues()
    end
  end
end
