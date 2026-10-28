defmodule OptimumCredo.Check.Warning.ExplicitIndexNameTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.ExplicitIndexName

  @path "priv/repo/migrations/20260101000000_add_index.exs"

  defp run(statement, params \\ [], path \\ @path) do
    """
    defmodule MyApp.Repo.Migrations.AddIndex do
      use Ecto.Migration

      def change do
        #{statement}
      end
    end
    """
    |> to_source_file(path)
    |> run_check(ExplicitIndexName, params)
  end

  test "it reports an explicit name on a single-column index" do
    "create index(:users, [:email], name: :users_email_idx)"
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 5 end)

    "create unique_index(:users, [:email], name: \"custom\")"
    |> run()
    |> assert_issue()

    "create_if_not_exists index(:users, :email, name: :custom)"
    |> run()
    |> assert_issue()

    "create index(:users, [:email], name: :users_email_index, unique: true)"
    |> run()
    |> assert_issue()
  end

  test "it accepts inferred names" do
    "create index(:users, [:email])"
    |> run()
    |> refute_issues()

    "create unique_index(:users, [:email], where: \"deleted_at is null\")"
    |> run()
    |> refute_issues()

    "create index(:users, [:email], concurrently: true)"
    |> run()
    |> refute_issues()
  end

  test "it accepts explicit names on multi-column and expression indexes by default" do
    "create index(:users, [:org_id, :email], name: :users_lookup)"
    |> run()
    |> refute_issues()

    ~s|create unique_index(:users, ["lower(email)"], name: :users_email_ci)|
    |> run()
    |> refute_issues()
  end

  test "allow_multi_column: false reports multi-column names but never expression indexes" do
    "create index(:users, [:org_id, :email], name: :users_lookup)"
    |> run(allow_multi_column: false)
    |> assert_issue()

    ~s|create unique_index(:users, ["lower(email)"], name: :users_email_ci)|
    |> run(allow_multi_column: false)
    |> refute_issues()
  end

  test "it does not inspect drop or non-literal columns" do
    "drop index(:users, [:email], name: :users_email_idx)"
    |> run()
    |> refute_issues()

    "create index(:users, columns, name: :users_email_idx)"
    |> run()
    |> refute_issues()

    ~s|execute("CREATE INDEX x ON users (email)") # name: :a|
    |> run()
    |> refute_issues()
  end

  test "it ignores a name option that is not on an index call" do
    "create constraint(:users, :email_present, check: \"email <> ''\", name: :x)"
    |> run()
    |> refute_issues()

    ~s|add :name, :string, [:email]|
    |> run()
    |> refute_issues()
  end

  test "it only checks migrations and honours ignore_files" do
    statement = "create index(:users, [:email], name: :users_email_idx)"

    statement
    |> run([], "lib/my_app/schema.ex")
    |> refute_issues()

    statement
    |> run(ignore_files: ["20260101000000_add_index.exs"])
    |> refute_issues()
  end

  describe "review regressions" do
    test "a named partial index is accepted by default" do
      statement =
        ~s|create unique_index(:users, [:email], name: :users_email_active, where: "deleted_at IS NULL")|

      statement
      |> run()
      |> refute_issues()

      statement
      |> run(allow_partial_indexes: false)
      |> assert_issue()
    end

    test "a name is accepted when the inferred one would exceed 63 bytes" do
      "create index(:organization_membership_invitations, [:invited_by_user_identifier], name: :short)"
      |> run()
      |> refute_issues()

      "create index(:users, [:invited_by_user_identifier], name: :short)"
      |> run()
      |> assert_issue()
    end

    test "compound index names are accepted and reported with allow_multi_column: false" do
      statement = "create unique_index(:memberships, [:org_id, :user_id], name: :membership_pair)"

      statement
      |> run()
      |> refute_issues()

      statement
      |> run(allow_multi_column: false)
      |> assert_issue()
    end

    test "drop index and non-literal column lists are left alone" do
      "drop index(:users, [:email], name: :users_email_idx)"
      |> run()
      |> refute_issues()

      "create index(:users, columns, name: :custom)"
      |> run()
      |> refute_issues()
    end
  end
end
