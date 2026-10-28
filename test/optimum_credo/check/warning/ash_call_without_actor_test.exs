defmodule OptimumCredo.Check.Warning.AshCallWithoutActorTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.AshCallWithoutActor

  defp run(body, params \\ [ash: true], path \\ "lib/my_app/blog.ex", header \\ "") do
    """
    defmodule MyApp.Blog do
      #{header}

      def run(user, id, opts) do
        #{body}
      end
    end
    """
    |> to_source_file(path)
    |> run_check(AshCallWithoutActor, params)
  end

  test "it reports Ash calls on a resource without actor" do
    for call <- [
          "Ash.read!(MyApp.Blog.Post)",
          "Ash.get(MyApp.Blog.Post, id)",
          "Ash.create!(MyApp.Blog.Post, %{title: \"x\"})",
          "Ash.destroy(MyApp.Blog.Post, tenant: user.org)",
          "MyApp.Blog.Post |> Ash.read!()",
          "MyApp.Blog.Post |> Ash.get!(id, load: [:comments])"
        ] do
      call
      |> run()
      |> assert_issue()
    end
  end

  test "it reports the Ash function and line" do
    "Ash.update!(MyApp.Blog.Post, %{})"
    |> run()
    |> assert_issue(fn issue ->
      assert issue.trigger == "update!"
      assert issue.line_no == 5
    end)
  end

  test "it accepts actor, authorize? and opaque options" do
    """
    Ash.read!(MyApp.Blog.Post, actor: user)
    MyApp.Blog.Post |> Ash.read!(actor: user, tenant: user.org)
    Ash.get(MyApp.Blog.Post, id, authorize?: false)
    Ash.read!(MyApp.Blog.Post, opts)
    Ash.read!(MyApp.Blog.Post, Keyword.merge(opts, load: [:a]))
    Ash.read!(MyApp.Blog.Post, Ash.Context.to_opts(assigns))
    Ash.read!(MyApp.Blog.Post, [load: [:a]] ++ opts)
    """
    |> run()
    |> refute_issues()
  end

  test "it cannot see actors carried by queries or changesets" do
    """
    query |> Ash.read!()
    Ash.create!(changeset)
    MyApp.Blog.Post |> Ash.Query.for_read(:read, %{}, actor: user) |> Ash.read!()
    Ash.Changeset.for_create(MyApp.Blog.Post, :create, %{}) |> Ash.create!()
    """
    |> run()
    |> refute_issues()
  end

  test "it ignores non-Ash calls, other functions and strings" do
    """
    Enum.read!(MyApp.Blog.Post)
    Ash.Query.new(MyApp.Blog.Post)
    Ash.stop(MyApp.Blog.Post)
    "Ash.read!(MyApp.Blog.Post)"
    # Ash.read!(MyApp.Blog.Post)
    """
    |> run()
    |> refute_issues()
  end

  test "it honours actorless_resources" do
    call = "Ash.read!(MyApp.Catalog.Country)"

    call
    |> run(ash: true, actorless_resources: ["MyApp.Catalog.Country"])
    |> refute_issues()

    call
    |> run(ash: true, actorless_resources: ["MyApp.Other"])
    |> assert_issue()
  end

  test "it treats listed resource modules as code interfaces" do
    params = [ash: true, resource_modules: ["MyApp.Blog.Post"]]

    "MyApp.Blog.Post.list_posts!()"
    |> run(params)
    |> assert_issue()

    "MyApp.Blog.Post.list_posts!(actor: user)"
    |> run(params)
    |> refute_issues()

    "MyApp.Blog.Post.list_posts!(opts)"
    |> run(params)
    |> refute_issues()

    "MyApp.Blog.Post.list_posts!()"
    |> run()
    |> refute_issues()
  end

  test "it honours ash_functions" do
    "Ash.stream!(MyApp.Blog.Post)"
    |> run(ash: true)
    |> refute_issues()

    "Ash.stream!(MyApp.Blog.Post)"
    |> run(ash: true, ash_functions: [:stream!])
    |> assert_issue()
  end

  test "it is disabled unless ash: true" do
    "Ash.read!(MyApp.Blog.Post)"
    |> run([])
    |> refute_issues()

    "Ash.read!(MyApp.Blog.Post)"
    |> run(ash: false)
    |> refute_issues()
  end

  test "it only checks lib/ and skips modules with an implicit context" do
    call = "Ash.read!(MyApp.Blog.Post)"

    call
    |> run([ash: true], "test/my_app/blog_test.exs")
    |> refute_issues()

    call
    |> run([ash: true], "priv/repo/seeds.exs")
    |> refute_issues()

    call
    |> run([ash: true], "lib/my_app/blog/change.ex", "use Ash.Resource.Change")
    |> refute_issues()

    call
    |> run([ash: true], "lib/my_app/blog/check.ex", "use Ash.Policy.SimpleCheck")
    |> refute_issues()

    call
    |> run([ash: true], "lib/my_app/blog/resource.ex", "use Ash.Resource, domain: MyApp")
    |> assert_issue()
  end

  describe "review regressions" do
    test "authorize?: true without an actor is still reported, authorize?: false is a decision" do
      "Ash.read!(MyApp.Blog.Post, authorize?: true)"
      |> run()
      |> assert_issue()

      "Ash.read!(MyApp.Blog.Post, authorize?: false)"
      |> run()
      |> refute_issues()

      "Ash.read!(MyApp.Blog.Post, authorize?: skip?)"
      |> run()
      |> refute_issues()
    end

    test "aliases are resolved for resources and for actorless_resources" do
      "Ash.read!(Post)"
      |> run([ash: true], "lib/my_app/blog.ex", "alias MyApp.Blog.Post")
      |> assert_issue()

      for actorless <- [["MyApp.Blog.Post"], [MyApp.Blog.Post]] do
        "Ash.read!(Post)"
        |> run(
          [ash: true, actorless_resources: actorless],
          "lib/my_app/blog.ex",
          "alias MyApp.Blog.Post"
        )
        |> refute_issues()
      end
    end

    test "resource_modules accepts strings or atoms and aliased receivers" do
      for modules <- [["MyApp.Blog.Post"], [MyApp.Blog.Post]] do
        "Post.create!(%{})"
        |> run(
          [ash: true, resource_modules: modules],
          "lib/my_app/blog.ex",
          "alias MyApp.Blog.Post"
        )
        |> assert_issue()
      end
    end

    test "same-named functions on unrelated modules are not Ash calls" do
      "Repo.read!(MyApp.Blog.Post)"
      |> run()
      |> refute_issues()

      "read!(MyApp.Blog.Post)"
      |> run()
      |> refute_issues()

      "Ash.Query.read!(MyApp.Blog.Post)"
      |> run()
      |> refute_issues()
    end

    test "the gate and the lib/ scope hold" do
      "Ash.read!(MyApp.Blog.Post)"
      |> run(ash: false)
      |> refute_issues()

      "Ash.read!(MyApp.Blog.Post)"
      |> run([ash: true], "test/my_app/blog_test.exs")
      |> refute_issues()
    end
  end
end
