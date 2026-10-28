defmodule OptimumCredo.Check.Warning.RepoCallInEnumerationTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.RepoCallInEnumeration

  defp run(source, params \\ [], path \\ "lib/my_app/posts.ex") do
    """
    defmodule MyApp.Posts do
      def run(posts) do
        #{source}
      end
    end
    """
    |> to_source_file(path)
    |> run_check(RepoCallInEnumeration, params)
  end

  test "it reports Repo queries inside Enum callbacks" do
    for call <- [
          "Enum.map(posts, fn post -> Repo.get(User, post.user_id) end)",
          "Enum.each(posts, fn post -> Repo.preload(post, :comments) end)",
          "Enum.flat_map(posts, &Repo.all(from c in Comment, where: c.post_id == ^&1.id))",
          "posts |> Enum.filter(fn post -> Repo.exists?(from c in Comment, where: c.post_id == ^post.id) end)",
          "Enum.reduce(posts, 0, fn post, acc -> acc + Repo.aggregate(Comment, :count) end)",
          "Stream.map(posts, &MyApp.Repo.reload!/1)",
          "Enum.map(posts, fn post -> post |> Repo.preload(:author) end)"
        ] do
      call
      |> run()
      |> assert_issue()
    end
  end

  test "it reports the Repo call line and trigger" do
    """
    Enum.map(posts, fn post ->
      Repo.get_by(User, id: post.user_id)
    end)
    """
    |> run()
    |> assert_issue(fn issue ->
      assert issue.line_no == 4
      assert issue.trigger == "Repo.get_by"
    end)
  end

  test "it reports nested enumerations once" do
    """
    Enum.map(posts, fn post ->
      Enum.map(post.tags, fn tag -> Repo.get(Tag, tag) end)
    end)
    """
    |> run()
    |> assert_issue()
  end

  test "it reports for comprehensions: body, filters and later generators" do
    "for post <- posts, do: Repo.get(User, post.user_id)"
    |> run()
    |> assert_issue()

    "for post <- posts, Repo.exists?(Comment), do: post"
    |> run()
    |> assert_issue()

    "for post <- posts, tag <- Repo.all(Tag), do: {post, tag}"
    |> run()
    |> assert_issue()

    "for post <- posts do\n  Repo.preload(post, :author)\nend"
    |> run()
    |> assert_issue()
  end

  test "it accepts queries outside of the loop and the first generator collection" do
    """
    users = Repo.all(User)
    for post <- Repo.all(Post), do: post.title
    Enum.map(posts, fn post -> {post, Map.get(users, post.user_id)} end)
    Repo.get(User, posts |> hd() |> Map.fetch!(:user_id))
    Enum.map(Repo.all(Post), & &1.title)
    """
    |> run()
    |> refute_issues()
  end

  test "it accepts writes and bulk operations by default, and non-Repo receivers" do
    "Enum.each(posts, fn post -> Repo.update!(post) end)"
    |> run()
    |> refute_issues()

    "Enum.map(posts, fn post -> Cache.get(post.id) end)"
    |> run()
    |> refute_issues()

    "Enum.map(posts, fn post -> Map.get(post, :id) end)"
    |> run()
    |> refute_issues()

    "Enum.map(posts, &Repo.get/2)"
    |> run()
    |> assert_issue()
  end

  test "it ignores strings and comments" do
    ~s|Enum.map(posts, fn post -> "Repo.get(\#{post})" end)|
    |> run()
    |> refute_issues()

    "# Enum.map(posts, fn post -> Repo.get(User, post) end)"
    |> run()
    |> refute_issues()
  end

  test "it honours the repo_functions and enumerator_functions parameters" do
    update = "Enum.each(posts, fn post -> Repo.update!(post) end)"

    update
    |> run(repo_functions: [:update!])
    |> assert_issue()

    sort = "Enum.zip_with(posts, posts, fn a, b -> Repo.get(User, a) end)"

    sort
    |> run()
    |> refute_issues()

    sort
    |> run(enumerator_functions: [:zip_with])
    |> assert_issue()
  end

  test "it skips ignored paths" do
    source = "Enum.map(posts, fn post -> Repo.get(User, post) end)"

    source
    |> run([], "test/my_app/posts_test.exs")
    |> refute_issues()

    source
    |> run([], "priv/repo/seeds.exs")
    |> refute_issues()

    source
    |> run([ignore_paths: []], "test/my_app/posts_test.exs")
    |> assert_issue()
  end

  describe "review regressions" do
    test "it follows an alias of the repo and ignores a non-repo module named Repo" do
      """
      defmodule MyApp.Posts do
        alias MyApp.Repo, as: R
        alias MyApp.Cache, as: Repo

        def run(posts) do
          Enum.map(posts, fn post -> R.get(User, post.user_id) end)
          Enum.map(posts, fn post -> Repo.get(post.user_id) end)
        end
      end
      """
      |> to_source_file("lib/my_app/posts.ex")
      |> run_check(RepoCallInEnumeration, [])
      |> assert_issue(fn issue -> assert issue.line_no == 6 end)
    end

    test "a query outside the per-element function is not reported" do
      """
      users = Repo.all(User)
      Enum.map(posts, fn post -> {post, users} end)
      Enum.map(Repo.all(Post), fn post -> post.id end)
      """
      |> run()
      |> refute_issues()
    end

    test "directory checks look at the path inside the project, not at its ancestors" do
      cwd = File.cwd!()
      ancestor = Path.basename(cwd)
      call = "Enum.map(posts, fn post -> Repo.get(User, post.user_id) end)"

      # An absolute path below the working directory is judged relative to it, so a project
      # that lives below a directory called `test` (or here: its own name) is still checked.
      call
      |> run([ignore_paths: [ancestor <> "/"]], Path.join(cwd, "lib/my_app/posts.ex"))
      |> assert_issue()

      call
      |> run([], Path.join(cwd, "test/posts_test.exs"))
      |> refute_issues()
    end
  end
end
