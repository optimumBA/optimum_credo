defmodule OptimumCredo.Check.Refactor.SchemaTableNameMismatchTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Refactor.SchemaTableNameMismatch

  defp run(module, table, params \\ [], extra \\ "") do
    """
    defmodule #{module} do
      use Ecto.Schema
      #{extra}

      schema "#{table}" do
        field :title, :string
      end
    end
    """
    |> to_source_file("lib/my_app/schema.ex")
    |> run_check(SchemaTableNameMismatch, params)
  end

  test "it reports a table with a different concept than the module" do
    "MyApp.Quiz.Question"
    |> run("user_questions")
    |> assert_issue(fn issue ->
      assert issue.message =~ "user_questions"
      assert issue.message =~ "questions"
      assert issue.line_no == 5
      assert issue.trigger == "user_questions"
    end)
  end

  test "it reports a singular table name and unrelated names" do
    "MyApp.Accounts.User"
    |> run("user")
    |> assert_issue()

    "MyApp.Accounts.User"
    |> run("accounts")
    |> assert_issue()

    "MyApp.Accounts.User"
    |> run("accounts_users")
    |> assert_issue()
  end

  test "it accepts regular plurals" do
    for {module, table} <- [
          {"MyApp.Accounts.User", "users"},
          {"MyApp.Blog.Post", "posts"},
          {"MyApp.Shop.Category", "categories"},
          {"MyApp.Shop.Box", "boxes"},
          {"MyApp.Shop.Address", "addresses"},
          {"MyApp.Shop.Bus", "buses"},
          {"MyApp.Shop.Key", "keys"},
          {"MyApp.Shop.Leaf", "leaves"},
          {"MyApp.Blog.PostComment", "post_comments"},
          {"MyApp.Blog.UserStory", "user_stories"}
        ] do
      module
      |> run(table)
      |> refute_issues()
    end
  end

  test "it accepts irregular plurals and uncountable words" do
    for {module, table} <- [
          {"MyApp.People.Person", "people"},
          {"MyApp.Kids.Child", "children"},
          {"MyApp.Stats.Datum", "data"},
          {"MyApp.Stats.Series", "series"},
          {"MyApp.Team.TeamMember", "team_members"}
        ] do
      module
      |> run(table)
      |> refute_issues()
    end
  end

  test "it compares the table without its schema prefix" do
    "MyApp.Accounts.User"
    |> run("public.users")
    |> refute_issues()

    "MyApp.Accounts.User"
    |> run("public.people")
    |> assert_issue()
  end

  test "it honours custom_inflections in both directions" do
    "MyApp.Zoo.Moose"
    |> run("mooses")
    |> refute_issues()

    "MyApp.Zoo.Moose"
    |> run("meese", custom_inflections: %{"moose" => "meese"})
    |> refute_issues()

    "MyApp.Zoo.Moose"
    |> run("meese", custom_inflections: %{moose: "meese"})
    |> refute_issues()

    "MyApp.Zoo.Moose"
    |> run("meese")
    |> assert_issue()
  end

  test "it honours the @credo_table_name_ok opt-out" do
    "MyApp.Quiz.Question"
    |> run("user_questions", [], "@credo_table_name_ok true")
    |> refute_issues()

    "MyApp.Quiz.Question"
    |> run("user_questions", [], "@credo_table_name_ok false")
    |> assert_issue()
  end

  test "it ignores embedded_schema, dynamic table names and other schema functions" do
    """
    defmodule MyApp.Quiz.Question do
      use Ecto.Schema

      embedded_schema do
        field :title, :string
      end

      def schema(name), do: name
    end

    defmodule MyApp.Quiz.Answer do
      @table "other"
      schema @table do
      end
    end
    """
    |> to_source_file("lib/my_app/schema.ex")
    |> run_check(SchemaTableNameMismatch)
    |> refute_issues()
  end

  test "it attributes schemas in nested and sibling modules to their own module" do
    """
    defmodule MyApp.Outer do
      defmodule Inner do
        use Ecto.Schema

        schema "wrong" do
        end
      end

      defmodule Item do
        use Ecto.Schema

        schema "items" do
        end
      end
    end
    """
    |> to_source_file("lib/my_app/outer.ex")
    |> run_check(SchemaTableNameMismatch)
    |> assert_issue(fn issue -> assert issue.message =~ "Inner" end)
  end

  describe "review regressions" do
    test "it accepts further English plurals" do
      for {module, table} <- [
            {"MyApp.Quiz", "quizzes"},
            {"MyApp.Hero", "heroes"},
            {"MyApp.Life", "lives"},
            {"MyApp.Knife", "knives"},
            {"MyApp.Data", "data"},
            {"MyApp.Metadata", "metadata"},
            {"MyApp.Matrix", "matrices"},
            {"MyApp.Status", "statuses"},
            {"MyApp.Category", "categories"},
            {"MyApp.Box", "boxes"}
          ] do
        module
        |> run(table)
        |> refute_issues()
      end
    end

    test "it reports a singular table name" do
      "MyApp.Accounts.User"
      |> run("user")
      |> assert_issue()
    end

    test "custom_inflections accept atom keys and apply to the last word only" do
      "MyApp.Blog.Draft"
      |> run("drafts_v2", custom_inflections: %{"draft" => "drafts_v2"})
      |> refute_issues()
    end

    test "a nested module is judged by its own name and a quoted template is ignored" do
      """
      defmodule MyApp.Outer do
        defmodule Inner do
          use Ecto.Schema

          schema "widgets" do
          end
        end

        defmacro __using__(_) do
          quote do
            defmodule Template do
              schema "anything" do
              end
            end
          end
        end
      end
      """
      |> to_source_file("lib/my_app/outer.ex")
      |> run_check(SchemaTableNameMismatch, [])
      |> assert_issue(fn issue ->
        assert issue.message =~ "Inner"
        assert issue.line_no == 5
      end)
    end
  end

  describe "false-positive regressions" do
    test "accepts the pluralised-words table that phx.gen.auth generates" do
      "MyApp.Accounts.UserToken"
      |> run("users_tokens")
      |> refute_issues()

      "MyApp.Blog.PostTag"
      |> run("posts_tags")
      |> refute_issues()

      "MyApp.Blog.PostTag"
      |> run("post_tags")
      |> refute_issues()
    end

    test "still reports tables whose words do not match the module" do
      "MyApp.Accounts.UserToken"
      |> run("users_sessions")
      |> assert_issue()

      "MyApp.Accounts.UserToken"
      |> run("tokens_users")
      |> assert_issue()
    end

    test "context-prefixed tables are reported by default" do
      "MyApp.Library.Follow"
      |> run("library_follows")
      |> assert_issue()
    end

    test "allow_context_prefix accepts the schema's own context as a prefix" do
      opts = [allow_context_prefix: true]

      "MyApp.Library.Follow"
      |> run("library_follows", opts)
      |> refute_issues()

      "MyApp.Memberships.Reservation"
      |> run("membership_reservations", opts)
      |> refute_issues()

      "MyApp.Podcasts.EpisodeTranscription"
      |> run("podcast_episode_transcriptions", opts)
      |> refute_issues()

      "MyApp.Memberships.Audit"
      |> run("memberships_audits", opts)
      |> refute_issues()
    end

    test "allow_context_prefix does not accept a different prefix" do
      opts = [allow_context_prefix: true]

      "MyApp.Accounts.Question"
      |> run("user_questions", opts)
      |> assert_issue()

      "MyApp.Library"
      |> run("library_follows", opts)
      |> assert_issue()
    end
  end
end
