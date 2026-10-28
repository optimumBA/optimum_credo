defmodule OptimumCredo.Check.Warning.AshUpsertOptionsTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.AshUpsertOptions

  defp run(source, params \\ [ash: true]) do
    source
    |> to_source_file("lib/my_app/blog.ex")
    |> run_check(AshUpsertOptions, params)
  end

  test "it reports upsert options in call keyword lists without upsert?: true" do
    """
    defmodule MyApp.Blog do
      def a, do: Ash.create!(changeset, upsert_identity: :unique_slug)
      def b, do: Ash.bulk_create(rows, Post, :create, upsert_fields: [:title])
      def c, do: Ash.create!(changeset, upsert?: false, upsert_identity: :unique_slug)
    end
    """
    |> run()
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.line_no, &1.trigger}) ==
               [{2, "upsert_identity"}, {3, "upsert_fields"}, {4, "upsert_identity"}]
    end)
  end

  test "it reports the DSL form without upsert? true" do
    """
    defmodule MyApp.Blog.Post do
      actions do
        create :register do
          upsert_identity :unique_slug
          upsert_fields [:title]
        end

        create :single do
          upsert_fields [:title]
        end
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [4, 5, 9] end)
  end

  test "it accepts upsert?: true in either form" do
    """
    defmodule MyApp.Blog.Post do
      actions do
        create :register do
          upsert? true
          upsert_identity :unique_slug
          upsert_fields [:title]
        end

        create :other, upsert?: true do
          upsert_identity :unique_slug
        end
      end

      def a, do: Ash.create!(changeset, upsert?: true, upsert_identity: :unique_slug)
      def b, do: Ash.create!(changeset, upsert_identity: :unique_slug, upsert?: upsert)
      def c, do: Ash.create!(changeset, opts)
    end
    """
    |> run()
    |> refute_issues()
  end

  test "it ignores strings, comments and unrelated options" do
    """
    defmodule MyApp.Blog do
      # Ash.create!(changeset, upsert_identity: :unique_slug)
      def a, do: "upsert_identity: :unique_slug"
      def b, do: Ash.create!(changeset, upsert?: true)
      def c, do: Ash.create!(changeset, upsert: true)
    end
    """
    |> run()
    |> refute_issues()
  end

  test "it is disabled unless ash: true" do
    source = "defmodule A do\n  def a, do: Ash.create!(changeset, upsert_identity: :x)\nend\n"

    source
    |> run([])
    |> refute_issues()

    source
    |> run(ash: false)
    |> refute_issues()
  end

  describe "review regressions" do
    test "upsert? enabled in the block covers an upsert_identity option of the action" do
      """
      defmodule MyApp.Blog.Post do
        actions do
          create :register, upsert_identity: :unique_email do
            upsert? true
          end

          create :other, upsert?: true, upsert_identity: :unique_email
          create :third, upsert_identity: :unique_email
        end
      end
      """
      |> run()
      |> assert_issue(fn issue -> assert issue.line_no == 8 end)
    end

    test "upsert? set through a variable counts as enabled" do
      """
      defmodule MyApp.Blog do
        def a(upsert?), do: Ash.create!(cs, upsert?: upsert?, upsert_identity: :unique_slug)
      end
      """
      |> run()
      |> refute_issues()
    end

    test "a DSL block with upsert_fields and no upsert? is reported at the statement" do
      """
      defmodule MyApp.Blog.Post do
        actions do
          create :register do
            upsert_fields [:title]
          end
        end
      end
      """
      |> run()
      |> assert_issue(fn issue ->
        assert issue.line_no == 4
        assert issue.trigger == "upsert_fields"
      end)
    end
  end
end
