defmodule OptimumCredo.Check.Warning.ReferenceWithoutOnDeleteTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.ReferenceWithoutOnDelete

  @path "priv/repo/migrations/20260101000000_add_posts.exs"

  defp run(statement, params \\ [], path \\ @path) do
    """
    defmodule MyApp.Repo.Migrations.AddPosts do
      use Ecto.Migration

      def change do
        create table(:posts) do
          #{statement}
        end
      end
    end
    """
    |> to_source_file(path)
    |> run_check(ReferenceWithoutOnDelete, params)
  end

  test "it reports references without options or without on_delete" do
    "add :user_id, references(:users)"
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 6 end)

    "add :user_id, references(:users, type: :binary_id)"
    |> run()
    |> assert_issue()

    "add :user_id, references(:users, type: :binary_id), null: false"
    |> run()
    |> assert_issue()

    "add :user_id, Ecto.Migration.references(:users, column: :id)"
    |> run()
    |> assert_issue()
  end

  test "it accepts any explicit on_delete" do
    "add :user_id, references(:users, on_delete: :delete_all)"
    |> run()
    |> refute_issues()

    "add :user_id, references(:users, on_delete: :nothing)"
    |> run()
    |> refute_issues()

    "add :user_id, references(:users, type: :uuid, on_delete: :nilify_all)"
    |> run()
    |> refute_issues()

    "add :user_id, references(:users, on_delete: strategy)"
    |> run()
    |> refute_issues()
  end

  test "it cannot see options supplied through a variable" do
    "add :user_id, references(:users, opts)"
    |> run()
    |> refute_issues()
  end

  test "it reports every reference in the file" do
    """
    add :user_id, references(:users)
    add :org_id, references(:orgs, on_delete: :delete_all)
    add :team_id, references(:teams)
    """
    |> run()
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [6, 8] end)
  end

  test "it ignores strings, comments and other functions" do
    ~s|add :note, :string, default: "references(:users)"|
    |> run()
    |> refute_issues()

    "# add :user_id, references(:users)"
    |> run()
    |> refute_issues()

    "add :user_id, :integer"
    |> run()
    |> refute_issues()
  end

  test "it honours require_on_delete: false, ignore_files and filename scope" do
    statement = "add :user_id, references(:users)"

    statement
    |> run(require_on_delete: false)
    |> refute_issues()

    statement
    |> run(ignore_files: ["20260101000000_add_posts.exs"])
    |> refute_issues()

    statement
    |> run([], "lib/my_app/posts.ex")
    |> refute_issues()
  end

  describe "review regressions" do
    test "the from: option of modify only describes the old column" do
      "modify :user_id, references(:users, on_delete: :nothing), from: references(:users)"
      |> run()
      |> refute_issues()

      "modify :user_id, references(:users), from: references(:users, on_delete: :nothing)"
      |> run()
      |> assert_issue()
    end

    test "dynamic on_delete values and option variables are not reported" do
      "add :user_id, references(:users, on_delete: @on_delete)"
      |> run()
      |> refute_issues()

      "add :user_id, references(:users, opts)"
      |> run()
      |> refute_issues()

      "add :user_id, references(:users, [type: :uuid] ++ opts)"
      |> run()
      |> refute_issues()
    end

    test "it recognises a qualified or aliased Ecto.Migration.references" do
      """
      defmodule MyApp.Repo.Migrations.AddPosts do
        use Ecto.Migration
        alias Ecto.Migration, as: M

        def change do
          alter table(:posts) do
            add :a_id, Ecto.Migration.references(:users)
            add :b_id, M.references(:users)
            add :c_id, M.references(:users, on_delete: :nothing)
          end
        end
      end
      """
      |> to_source_file(@path)
      |> run_check(ReferenceWithoutOnDelete, [])
      |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [7, 8] end)
    end

    test "a different type option does not count as on_delete" do
      "add :user_id, references(:users, type: :uuid, name: \"fk\")"
      |> run()
      |> assert_issue()
    end
  end
end
