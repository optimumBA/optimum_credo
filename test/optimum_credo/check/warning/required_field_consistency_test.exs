defmodule OptimumCredo.Check.Warning.RequiredFieldConsistencyTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.RequiredFieldConsistency

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "required_field_consistency_#{System.unique_integer([:positive])}"
      )

    root
    |> Path.join("priv/repo/migrations")
    |> File.mkdir_p!()

    on_exit(fn -> File.rm_rf!(root) end)

    migration(root, "20260101000000_create_posts.exs", """
    defmodule MyApp.Repo.Migrations.CreatePosts do
      use Ecto.Migration

      def change do
        create table(:posts) do
          add :title, :string, null: false
          add :body, :text
          add :slug, :string, null: false, default: ""
          add :user_id, references(:users, on_delete: :delete_all), null: false
          add :status, :string, null: false
          timestamps()
        end
      end
    end
    """)

    %{root: root}
  end

  defp migration(root, name, source) do
    [root, "priv/repo/migrations", name]
    |> Path.join()
    |> File.write!(source)
  end

  defp run(root, source, params \\ []) do
    source
    |> to_source_file(Path.join(root, "lib/my_app/post.ex"))
    |> run_check(RequiredFieldConsistency, params)
  end

  defp schema(changeset, extra \\ "") do
    """
    defmodule MyApp.Blog.Post do
      use Ecto.Schema
      import Ecto.Changeset

      #{extra}

      schema "posts" do
        field :title, :string
        field :body, :string
        field :slug, :string
        field :status, :string
        belongs_to :user, MyApp.Accounts.User
        timestamps()
      end

      #{changeset}
    end
    """
  end

  test "it reports NOT NULL columns missing from validate_required", %{root: root} do
    root
    |> run(
      schema("""
      def changeset(post, attrs) do
        post |> cast(attrs, [:title, :body, :status, :user_id]) |> validate_required([:title])
      end
      """)
    )
    |> assert_issues(fn issues ->
      assert issues
             |> Enum.map(& &1.trigger)
             |> Enum.sort() == ["status", "user_id"]

      assert Enum.all?(issues, &(&1.line_no >= 9))
    end)
  end

  test "it accepts fully validated, defaulted and associated columns", %{root: root} do
    root
    |> run(
      schema("""
      def changeset(post, attrs) do
        post |> cast(attrs, [:title, :status, :user_id]) |> validate_required([:title, :status, :user])
      end
      """)
    )
    |> refute_issues()
  end

  test "it resolves attributes, ++ and piped validate_required", %{root: root} do
    root
    |> run(
      schema(
        """
        def changeset(post, attrs) do
          post |> cast(attrs, @required ++ @optional) |> validate_required(@required ++ [:user_id])
        end
        """,
        "@required [:title]\n@optional [:body]"
      )
    )
    |> assert_issue(fn issue -> assert issue.trigger == "status" end)
  end

  test "it exempts schema defaults, system-set fields and ignore_fields", %{root: root} do
    source =
      schema("""
      def changeset(post, attrs) do
        post |> cast(attrs, [:title]) |> validate_required([:title]) |> put_change(:status, "draft")
      end
      """)

    root
    |> run(source)
    |> assert_issue(fn issue -> assert issue.trigger == "user_id" end)

    root
    |> run(source, ignore_fields: [:user_id])
    |> refute_issues()

    root
    |> run(
      String.replace(
        source,
        "field :title",
        "field :title, :string, default: \"\"\n    field :other"
      )
    )
    |> assert_issue()
  end

  test "it replays later migrations: modify null, remove and defaults", %{root: root} do
    migration(root, "20260102000000_relax.exs", """
    defmodule MyApp.Repo.Migrations.Relax do
      use Ecto.Migration

      def change do
        alter table(:posts) do
          modify :title, :string, null: true
          remove :status
          add :body, :text, null: false
          modify :user_id, references(:users), default: 1
        end
      end
    end
    """)

    root
    |> run(
      schema("""
      def changeset(post, attrs), do: post |> cast(attrs, [:body]) |> validate_required([:user_id])
      """)
    )
    |> assert_issue(fn issue -> assert issue.trigger == "body" and not is_nil(issue.line_no) end)
  end

  test "it stays silent without validate_required or with unresolvable arguments", %{root: root} do
    root
    |> run(schema("def changeset(post, attrs), do: cast(post, attrs, [:title])"))
    |> refute_issues()

    root
    |> run(schema("def changeset(post, attrs), do: validate_required(post, required_fields())"))
    |> refute_issues()

    root
    |> run(schema("def changeset(post, attrs), do: validate_required(post, fields)"))
    |> refute_issues()
  end

  test "it stays silent for unknown tables, missing migrations and non-schema files", %{
    root: root
  } do
    posts_schema = schema("def changeset(post, attrs), do: validate_required(post, [:body])")
    comments_schema = String.replace(posts_schema, ~s|schema "posts"|, ~s|schema "comments"|)

    root
    |> run(comments_schema)
    |> refute_issues()

    missing = Path.join(root, "nowhere")

    missing
    |> run(posts_schema, migrations_path: "none")
    |> refute_issues()

    root
    |> run("defmodule MyApp.Plain do\n  def run, do: :ok\nend\n")
    |> refute_issues()
  end

  test "it honours migrations_path", %{root: root} do
    root
    |> Path.join("db/migrate")
    |> File.mkdir_p!()

    root
    |> Path.join("priv/repo/migrations/20260101000000_create_posts.exs")
    |> File.rename!(Path.join(root, "db/migrate/20260101000000_create_posts.exs"))

    source = schema("def changeset(post, attrs), do: validate_required(post, [:body])")

    root
    |> run(source)
    |> refute_issues()

    root
    |> run(source, migrations_path: "db/migrate")
    |> assert_issues()
  end

  test "it ignores embedded schemas and strings that look like schemas", %{root: root} do
    root
    |> run("""
    defmodule MyApp.Form do
      use Ecto.Schema
      embedded_schema do
        field :title, :string
      end
      def doc, do: "schema \\"posts\\" do end validate_required([:title])"
    end
    """)
    |> refute_issues()
  end

  describe "false-positive regressions" do
    test "execute SQL that drops NOT NULL loosens the column", %{root: root} do
      migration(root, "20260102000000_loosen_body.exs", """
      defmodule MyApp.Repo.Migrations.LoosenTitle do
        use Ecto.Migration

        def change do
          execute(
            "ALTER TABLE posts ALTER COLUMN title DROP NOT NULL",
            "ALTER TABLE posts ALTER COLUMN title SET NOT NULL"
          )
        end
      end
      """)

      root
      |> run(
        schema("""
        def changeset(post, attrs) do
          post |> cast(attrs, [:title, :status, :user_id]) |> validate_required([:status, :user_id])
        end
        """)
      )
      |> refute_issues()
    end

    test "execute SQL that sets NOT NULL tightens the column", %{root: root} do
      migration(root, "20260102000000_require_body.exs", """
      defmodule MyApp.Repo.Migrations.RequireBody do
        use Ecto.Migration

        def up do
          execute "ALTER TABLE public.posts ALTER COLUMN body SET NOT NULL"
        end

        def down do
          execute "ALTER TABLE posts ALTER COLUMN body DROP NOT NULL"
        end
      end
      """)

      root
      |> run(
        schema("""
        def changeset(post, attrs) do
          post |> cast(attrs, [:title, :status, :user_id]) |> validate_required([:title, :status, :user_id])
        end
        """)
      )
      |> assert_issue(fn issue -> assert issue.trigger == "body" end)
    end
  end

  describe "review regressions" do
    test "def down is not replayed over def up", %{root: root} do
      migration(root, "20260102000000_body_required.exs", """
      defmodule MyApp.Repo.Migrations.BodyRequired do
        use Ecto.Migration

        def up do
          alter table(:posts) do
            modify :body, :text, null: false
          end
        end

        def down do
          alter table(:posts) do
            modify :body, :text, null: true
          end
        end
      end
      """)

      root
      |> run(
        schema("""
        def changeset(post, attrs) do
          post |> cast(attrs, [:title]) |> validate_required([:title, :status, :user_id])
        end
        """)
      )
      |> assert_issue(fn issue -> assert issue.trigger == "body" end)
    end

    test "drop table forgets the old columns", %{root: root} do
      migration(root, "20260102000000_recreate_posts.exs", """
      defmodule MyApp.Repo.Migrations.RecreatePosts do
        use Ecto.Migration

        def change do
          drop table(:posts)

          create table(:posts) do
            add :title, :string
          end
        end
      end
      """)

      root
      |> run(
        schema(
          "def changeset(post, attrs), do: validate_required(cast(post, attrs, []), [:body])"
        )
      )
      |> refute_issues()
    end

    test "a renamed column follows the rename", %{root: root} do
      migration(root, "20260102000000_rename_status.exs", """
      defmodule MyApp.Repo.Migrations.RenameStatus do
        use Ecto.Migration

        def change do
          rename table(:posts), :status, to: :state
        end
      end
      """)

      source = """
      defmodule MyApp.Blog.Post do
        use Ecto.Schema

        schema "posts" do
          field :title, :string
          field :state, :string
          belongs_to :user, MyApp.Accounts.User
        end

        def changeset(post, attrs), do: validate_required(post, [:title, :user])
      end
      """

      root
      |> run(source)
      |> assert_issue(fn issue -> assert issue.trigger == "state" end)
    end

    test "a source: option maps the field to its column, virtual fields have none", %{root: root} do
      source = """
      defmodule MyApp.Blog.Post do
        use Ecto.Schema

        schema "posts" do
          field :heading, :string, source: :title
          field :status, :string, virtual: true
          belongs_to :user, MyApp.Accounts.User, define_field: false
        end

        def changeset(post, attrs), do: validate_required(post, [:body])
      end
      """

      root
      |> run(source)
      |> assert_issue(fn issue -> assert issue.trigger == "title" end)
    end

    test "a field is satisfied by its schema name even when the column is renamed by source", %{
      root: root
    } do
      source = """
      defmodule MyApp.Blog.Post do
        use Ecto.Schema

        schema "posts" do
          field :heading, :string, source: :title
        end

        def changeset(post, attrs), do: validate_required(post, [:heading])
      end
      """

      root
      |> run(source)
      |> refute_issues()
    end

    test "the nearest project holding the migrations directory is used", %{root: root} do
      project = Path.join([root, "lib", "umbrella", "apps", "blog"])

      project
      |> Path.join("priv/repo/migrations")
      |> File.mkdir_p!()

      project
      |> Path.join("lib/my_app")
      |> File.mkdir_p!()

      project
      |> Path.join("priv/repo/migrations/20260101000000_create_posts.exs")
      |> File.write!("""
      defmodule MyApp.Repo.Migrations.CreatePosts do
        use Ecto.Migration

        def change do
          create table(:posts) do
            add :title, :string, null: false
          end
        end
      end
      """)

      source = """
      defmodule MyApp.Blog.Post do
        use Ecto.Schema

        schema "posts" do
          field :title, :string
        end

        def changeset(post, attrs), do: validate_required(post, [:other])
      end
      """

      source
      |> to_source_file(Path.join(project, "lib/my_app/post.ex"))
      |> run_check(RequiredFieldConsistency, [])
      |> assert_issue(fn issue -> assert issue.trigger == "title" end)
    end

    test "validate_required in a nested module does not satisfy the outer schema", %{root: root} do
      source = """
      defmodule MyApp.Blog.Post do
        use Ecto.Schema

        schema "posts" do
          field :title, :string
          field :status, :string
          belongs_to :user, MyApp.Accounts.User
        end

        def changeset(post, attrs), do: validate_required(post, [:title, :user])

        defmodule Form do
          def changeset(cs), do: validate_required(cs, [:status])
        end
      end
      """

      root
      |> run(source)
      |> assert_issue(fn issue -> assert issue.trigger == "status" end)
    end
  end

  test "column messages retain valid uppercase and Unicode atom spellings", %{root: root} do
    for column <- [:UserId, :foo@bar, :café, :ünïcode] do
      migration(root, "20260102000000_legacy_columns.exs", """
      defmodule MyApp.Repo.Migrations.LegacyColumns do
        use Ecto.Migration
        def change do
          create table(:legacy_columns) do
            add #{inspect(column)}, :integer, null: false
          end
        end
      end
      """)

      source = """
      defmodule MyApp.Legacy do
        use Ecto.Schema
        schema "legacy_columns" do
          field :owner, :integer, source: #{inspect(column)}
        end
        def changeset(record, attrs) do
          record
          |> cast(attrs, [:owner])
          |> validate_required([])
        end
      end
      """

      [issue] = run(root, source)
      assert String.starts_with?(issue.message, "Column #{inspect(column)} is `null: false`")
      assert issue.trigger == Atom.to_string(column)
    end
  end

  test "context put_assoc after the exact schema changeset supplies required associations", %{
    root: root
  } do
    directory = Path.join(root, "lib/my_app")
    File.mkdir_p!(directory)

    directory
    |> Path.join("blog.ex")
    |> File.write!(~S"""
    defmodule MyApp.Blog do
      import Ecto.Changeset, only: [put_assoc: 3]
      alias MyApp.Blog.Post
      def create(post, user, attrs) do
        post |> Post.changeset(attrs) |> put_assoc(:user, user)
      end
    end
    """)

    root
    |> run(
      schema("""
      def changeset(post, attrs) do
        post |> cast(attrs, [:title, :status]) |> validate_required([:title, :status])
      end
      """)
    )
    |> refute_issues()
  end

  test "unrelated changesets and same-named custom put_assoc do not exempt fields", %{root: root} do
    directory = Path.join(root, "lib/my_app")
    File.mkdir_p!(directory)

    directory
    |> Path.join("other.ex")
    |> File.write!(~S"""
    defmodule MyApp.Other do
      alias MyApp.Other.Post
      def create(post, user, attrs) do
        post |> Post.changeset(attrs) |> Ecto.Changeset.put_assoc(:user, user)
      end
      def custom(post, user, attrs) do
        post |> MyApp.Blog.Post.changeset(attrs) |> Custom.put_assoc(:user, user)
      end
    end
    """)

    root
    |> run(
      schema("""
      def changeset(post, attrs) do
        post |> cast(attrs, [:title, :status]) |> validate_required([:title, :status])
      end
      """)
    )
    |> assert_issue(fn issue -> assert issue.trigger == "user_id" end)
  end
end
