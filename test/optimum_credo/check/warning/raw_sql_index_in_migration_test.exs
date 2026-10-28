defmodule OptimumCredo.Check.Warning.RawSqlIndexInMigrationTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.RawSqlIndexInMigration

  @path "priv/repo/migrations/20260101000000_add_index.exs"

  defp run(statement, params \\ [], path \\ @path) do
    """
    defmodule MyApp.Repo.Migrations.AddIndex do
      use Ecto.Migration

      def up do
        #{statement}
      end
    end
    """
    |> to_source_file(path)
    |> run_check(RawSqlIndexInMigration, params)
  end

  test "it reports CREATE INDEX, CREATE UNIQUE INDEX and DROP INDEX in strings" do
    ~s|execute("CREATE INDEX users_email_index ON users (email)")|
    |> run()
    |> assert_issue()

    ~s|execute("create unique index users_email_index on users (email)")|
    |> run()
    |> assert_issue()

    ~s|execute("DROP INDEX users_email_index")|
    |> run()
    |> assert_issue()
  end

  test "it reports the up and down forms and reports the execute line" do
    ~s|execute("CREATE INDEX i ON t (a)", "DROP INDEX i")|
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 5 end)
  end

  test "it does not judge the rollback of an exempt CONCURRENTLY or expression create" do
    ~s|execute("CREATE INDEX CONCURRENTLY i ON users (email)", "DROP INDEX i")|
    |> run()
    |> refute_issues()

    ~s|execute("CREATE INDEX i ON users (lower(email))", "DROP INDEX i")|
    |> run()
    |> refute_issues()
  end

  test "it still reports a plain create/drop pair and a drop paired with non-index SQL" do
    ~s|execute("CREATE INDEX i ON users (email)", "DROP INDEX i")|
    |> run()
    |> assert_issue()

    ~s|execute("ALTER TABLE users ADD x int", "DROP INDEX i")|
    |> run()
    |> assert_issue()

    ~s|execute("CREATE INDEX i ON users (email)", "ALTER TABLE users DROP x")|
    |> run()
    |> assert_issue()
  end

  test "it judges the rollback again when the exemptions are disabled" do
    statement = ~s|execute("CREATE INDEX CONCURRENTLY i ON users (email)", "DROP INDEX i")|

    statement
    |> run(allow_concurrent: false)
    |> assert_issue()
  end

  test "it reports heredocs and sigils" do
    ~s|execute(~S"CREATE INDEX i ON t (a)")|
    |> run()
    |> assert_issue()

    ~s|execute(\"\"\"\n    CREATE INDEX i\n    ON t (a)\n    \"\"\")|
    |> run()
    |> assert_issue()
  end

  test "it reports interpolated SQL strings" do
    ~S|execute("CREATE INDEX #{name} ON t (a)")|
    |> run()
    |> assert_issue()
  end

  test "it accepts CONCURRENTLY by default and reports it when disabled" do
    statement = ~s|execute("CREATE INDEX CONCURRENTLY i ON t (a)")|

    statement
    |> run()
    |> refute_issues()

    statement
    |> run(allow_concurrent: false)
    |> assert_issue()
  end

  test "it accepts expression indexes by default and reports them when disabled" do
    statement = ~s|execute("CREATE UNIQUE INDEX i ON users (lower(email))")|

    statement
    |> run()
    |> refute_issues()

    statement
    |> run(allow_expression_indexes: false)
    |> assert_issue()

    ~s|execute("CREATE INDEX i ON users USING gin ((data->'tags'))")|
    |> run()
    |> refute_issues()

    ~s|execute("CREATE INDEX i ON users (email) WHERE lower(email) = 'x'")|
    |> run()
    |> assert_issue()
  end

  test "it ignores non-index SQL, DSL calls, variables and comments" do
    ~s|execute("ALTER TABLE users ADD COLUMN x int")|
    |> run()
    |> refute_issues()

    ~s|execute("CREATE EXTENSION IF NOT EXISTS citext")|
    |> run()
    |> refute_issues()

    ~s|create unique_index(:users, [:email])|
    |> run()
    |> refute_issues()

    ~s|execute(sql)|
    |> run()
    |> refute_issues()

    ~s|# execute("CREATE INDEX i ON t (a)")|
    |> run()
    |> refute_issues()

    ~s|IO.puts("CREATE INDEX i ON t (a)")|
    |> run()
    |> refute_issues()
  end

  test "it only checks migrations and honours ignore_files" do
    statement = ~s|execute("CREATE INDEX i ON t (a)")|

    statement
    |> run([], "lib/my_app/release.ex")
    |> refute_issues()

    statement
    |> run(ignore_files: ["20260101000000_add_index.exs"])
    |> refute_issues()

    statement
    |> run(ignore_files: ["add_index.exs"])
    |> assert_issue()
  end

  describe "review regressions" do
    test "it ignores index words inside SQL strings, comments and other statements" do
      for sql <- [
            ~s|execute("INSERT INTO notes (body) VALUES ('create index later')")|,
            ~s|execute("-- create index later\nUPDATE users SET active = true")|,
            ~s|execute("/* drop index x */ UPDATE users SET active = true")|,
            ~s|execute("COMMENT ON INDEX users_email_index IS 'create index'")|
          ] do
        sql
        |> run()
        |> refute_issues()
      end
    end

    test "it judges each statement of a multi-statement string on its own" do
      ~s|execute("CREATE INDEX CONCURRENTLY a ON t (x); CREATE INDEX b ON t (y)")|
      |> run()
      |> assert_issue()

      ~s|execute("CREATE INDEX CONCURRENTLY a ON t (x); CREATE INDEX CONCURRENTLY b ON t (y)")|
      |> run()
      |> refute_issues()

      ~s|execute("BEGIN; CREATE INDEX b ON t (y); COMMIT")|
      |> run()
      |> assert_issue()
    end

    test "a partial index over plain columns is still reported" do
      ~s|execute("CREATE INDEX b ON t (y) WHERE (deleted_at IS NULL)")|
      |> run()
      |> assert_issue()
    end

    test "an expression index is accepted by default and reported when disallowed" do
      sql = ~s|execute("CREATE INDEX b ON t (lower(email))")|

      sql
      |> run()
      |> refute_issues()

      sql
      |> run(allow_expression_indexes: false)
      |> assert_issue()
    end
  end
end
