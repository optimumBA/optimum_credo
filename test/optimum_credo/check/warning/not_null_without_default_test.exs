defmodule OptimumCredo.Check.Warning.NotNullWithoutDefaultTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.NotNullWithoutDefault

  @path "priv/repo/migrations/20260101000000_add_status.exs"

  defp run(body, params \\ [], path \\ @path) do
    """
    defmodule MyApp.Repo.Migrations.AddStatus do
      use Ecto.Migration

      def change do
        #{body}
      end
    end
    """
    |> to_source_file(path)
    |> run_check(NotNullWithoutDefault, params)
  end

  test "it reports a NOT NULL column added without default to an existing table" do
    """
    alter table(:users) do
      add :status, :string, null: false
    end
    """
    |> run()
    |> assert_issue(fn issue ->
      assert issue.message =~ ":status"
      assert issue.line_no == 6
    end)
  end

  test "it reports add_if_not_exists, references and default: nil" do
    """
    alter table(:users) do
      add_if_not_exists :status, :string, null: false
      add :org_id, references(:orgs), null: false
      add :flag, :boolean, null: false, default: nil
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert length(issues) == 3 end)
  end

  test "it accepts a default, nullable columns and an implicit-nullable add" do
    """
    alter table(:users) do
      add :status, :string, null: false, default: "active"
      add :flag, :boolean, default: false, null: false
      add :limit, :integer, null: false, default: limit_default()
      add :nickname, :string, null: true
      add :bio, :text
    end
    """
    |> run()
    |> refute_issues()
  end

  test "it does not report create table, modify or remove" do
    """
    create table(:users) do
      add :status, :string, null: false
    end

    alter table(:users) do
      modify :status, :string, null: false
      remove :legacy
    end
    """
    |> run()
    |> refute_issues()
  end

  test "it handles an alter block with a single statement and ignores unrelated adds" do
    "alter table(:users), do: add(:status, :string, null: false)"
    |> run()
    |> assert_issue()

    "add :status, :string, null: false"
    |> run()
    |> refute_issues()

    ~s|execute("ALTER TABLE users ADD COLUMN status text NOT NULL")|
    |> run()
    |> refute_issues()
  end

  test "it only checks migrations and honours ignore_files" do
    body = "alter table(:users) do\n  add :status, :string, null: false\nend"

    body
    |> run([], "lib/my_app/status.ex")
    |> refute_issues()

    body
    |> run(ignore_files: ["20260101000000_add_status.exs"])
    |> refute_issues()
  end

  describe "review regressions" do
    test "a table created by the same migration is empty when altered" do
      """
      create table(:posts) do
        add :title, :string
      end

      alter table(:posts) do
        add :status, :string, null: false
      end
      """
      |> run()
      |> refute_issues()
    end

    test "altering a table other than the one just created is still reported" do
      """
      create table(:tags) do
        add :name, :string
      end

      alter table(:posts) do
        add :status, :string, null: false
      end
      """
      |> run()
      |> assert_issue(fn issue -> assert issue.line_no == 10 end)
    end

    test "a default through a fragment or variable counts, nil does not" do
      """
      alter table(:posts) do
        add :a, :utc_datetime, null: false, default: fragment("now()")
        add :b, :integer, null: false, default: @zero
        add :c, :integer, null: false, default: nil
      end
      """
      |> run()
      |> assert_issue(fn issue -> assert issue.line_no == 8 end)
    end
  end
end
