defmodule OptimumCredo.Check.Readability.SchemaFieldOrderTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.SchemaFieldOrder

  test "reports the first out-of-order field in a run, once" do
    """
    defmodule Post do
      use Ecto.Schema

      schema "posts" do
        field :title, :string
        field :body, :string
        field :author, :string
      end
    end
    """
    |> to_source_file()
    |> run_check(SchemaFieldOrder)
    |> assert_issue(fn issue ->
      assert issue.line_no == 6
      assert issue.message =~ "body before title"
    end)
  end

  test "accepts sorted fields and associations declared together" do
    """
    defmodule Post do
      schema "posts" do
        belongs_to :author, User
        field :body, :string
        has_many :comments, Comment
        field :title, :string
        timestamps()
      end
    end
    """
    |> to_source_file()
    |> run_check(SchemaFieldOrder)
    |> refute_issues()
  end

  test "reports mixed fields and associations by declared name" do
    """
    defmodule Post do
      schema "posts" do
        field :body, :string
        belongs_to :author, User
        field :title, :string
      end
    end
    """
    |> to_source_file()
    |> run_check(SchemaFieldOrder)
    |> assert_issue(fn issue -> assert issue.line_no == 4 end)
  end

  test "group_associations orders fields and associations separately" do
    source = """
    defmodule Post do
      schema "posts" do
        field :body, :string
        belongs_to :author, User
        field :title, :string
        has_many :comments, Comment
      end
    end
    """

    source
    |> to_source_file()
    |> run_check(SchemaFieldOrder)
    |> assert_issue()

    source
    |> to_source_file()
    |> run_check(SchemaFieldOrder, group_associations: true)
    |> refute_issues()
  end

  test "other statements end a run and short runs are ignored" do
    """
    defmodule Post do
      schema "posts" do
        field :title, :string
        field :body, :string
        timestamps()
        field :author, :string
        field :abstract, :string
      end
    end
    """
    |> to_source_file()
    |> run_check(SchemaFieldOrder)
    |> refute_issues()
  end

  test "min_run is configurable" do
    """
    defmodule Post do
      schema "posts" do
        field :title, :string
        field :body, :string
      end
    end
    """
    |> to_source_file()
    |> run_check(SchemaFieldOrder, min_run: 2)
    |> assert_issue()
  end

  test "checks embedded_schema and nested embeds blocks independently" do
    """
    defmodule Address do
      embedded_schema do
        field :city, :string
        field :country, :string
        field :street, :string

        embeds_one :zone, Zone do
          field :lng, :float
          field :lat, :float
          field :zoom, :integer
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(SchemaFieldOrder)
    |> assert_issue(fn issue -> assert issue.line_no == 9 end)
  end

  test "ignores dynamic names, other macros and text mentioning fields" do
    ~S'''
    defmodule Post do
      def info, do: "field :b then field :a field :c"

      schema "posts" do
        field unquote(:b), :string
        field :a, :string
        field :c, :string
      end

      def field(:b), do: :ok
    end
    '''
    |> to_source_file()
    |> run_check(SchemaFieldOrder)
    |> refute_issues()
  end

  test "a realistic schema is checked per run, not across timestamps and attributes" do
    """
    defmodule MyApp.Posts.Post do
      use Ecto.Schema

      @primary_key {:id, :binary_id, autogenerate: true}

      schema "posts" do
        field :body, :string
        field :title, :string
        field :views, :integer, default: 0
        field :slug, :string, virtual: true

        belongs_to :author, MyApp.Accounts.User
        has_many :comments, MyApp.Posts.Comment

        timestamps()
      end
    end
    """
    |> to_source_file()
    |> run_check(SchemaFieldOrder)
    |> assert_issue(fn issue ->
      assert issue.line_no == 10
      assert issue.message =~ "slug before views"
    end)
  end

  test "group_associations accepts sorted fields followed by sorted associations only when grouped" do
    source = """
    defmodule MyApp.Posts.Post do
      use Ecto.Schema

      schema "posts" do
        field :body, :string
        field :title, :string
        field :views, :integer
        belongs_to :author, MyApp.Accounts.User
        belongs_to :blog, MyApp.Blogs.Blog
        has_many :comments, MyApp.Posts.Comment
      end
    end
    """

    source
    |> to_source_file()
    |> run_check(SchemaFieldOrder)
    |> assert_issue()

    source
    |> to_source_file()
    |> run_check(SchemaFieldOrder, group_associations: true)
    |> refute_issues()
  end

  test "group_associations still reports an unsorted association group" do
    """
    defmodule MyApp.Posts.Post do
      use Ecto.Schema

      schema "posts" do
        field :body, :string
        field :title, :string
        field :views, :integer
        has_many :comments, MyApp.Posts.Comment
        belongs_to :blog, MyApp.Blogs.Blog
        belongs_to :author, MyApp.Accounts.User
      end
    end
    """
    |> to_source_file()
    |> run_check(SchemaFieldOrder, group_associations: true)
    |> assert_issue(fn issue ->
      assert issue.line_no == 9
      assert issue.message =~ "blog before comments"
    end)
  end

  test "a blank-free run split by another macro is two runs below min_run" do
    """
    defmodule Demo do
      use Ecto.Schema

      schema "demo" do
        field :b, :string
        field :a, :string
        timestamps()
        field :d, :string
        field :c, :string
      end
    end
    """
    |> to_source_file()
    |> run_check(SchemaFieldOrder)
    |> refute_issues()
  end

  test "reports a descending run once and accepts duplicates names in order" do
    """
    defmodule Demo do
      use Ecto.Schema

      schema "demo" do
        field :c, :string
        field :b, :string
        field :a, :string
      end
    end
    """
    |> to_source_file()
    |> run_check(SchemaFieldOrder)
    |> assert_issue(fn issue -> assert issue.line_no == 6 end)
  end
end
