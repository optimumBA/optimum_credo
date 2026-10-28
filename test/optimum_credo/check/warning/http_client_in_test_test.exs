defmodule OptimumCredo.Check.Warning.HttpClientInTestTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.HttpClientInTest

  @file_name "test/my_app/client_test.exs"

  defp run(code, params \\ [], file \\ @file_name) do
    code
    |> to_source_file(file)
    |> run_check(HttpClientInTest, params)
  end

  test "reports HTTP client calls including erlang modules" do
    """
    defmodule ClientTest do
      use ExUnit.Case
      test "a" do
        HTTPoison.get!("https://example.com")
        Req.get("https://example.com")
        :httpc.request(:get, {~c"http://example.com", []}, [], [])
        Finch.request(request, MyFinch)
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert length(issues) == 4 end)
  end

  test "accepts mock definitions, plug options and local URLs" do
    """
    defmodule ClientTest do
      use ExUnit.Case
      test "a" do
        Bypass.expect(bypass, fn conn -> HTTPoison.get!("https://example.com") end)
        Mox.stub(HttpMock, :get, fn _ -> Req.get!("https://x") end)
        Req.get("https://example.com", plug: {Req.Test, MyStub})
        HTTPoison.get!("http://localhost:\#{bypass.port}/x")
        Req.get("http://127.0.0.1:4000")
        Req.Test.stub(MyStub, fn conn -> conn end)
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "ignores lookalikes, strings, quotes and non-test files" do
    code = """
    defmodule ClientTest do
      use ExUnit.Case
      test "a" do
        MyReq.get("x")
        Requests.get("x")
        assert "HTTPoison.get(x)" == "x"
        quote do
          Req.get("x")
        end
      end
    end
    """

    code
    |> run()
    |> refute_issues()

    "defmodule A do\n def a, do: Req.get(\"x\")\nend"
    |> run([], "lib/a.ex")
    |> refute_issues()
  end

  test "client_modules, allow_local_urls and mock_wrappers params" do
    code = """
    defmodule ClientTest do
      use ExUnit.Case
      test "a" do
        MyHttp.post("http://localhost/x")
        custom_mock(fn -> MyHttp.post("https://x") end)
      end
    end
    """

    code
    |> run()
    |> refute_issues()

    code
    |> run(client_modules: ["MyHttp"], mock_wrappers: [:custom_mock], allow_local_urls: false)
    |> assert_issue(fn issue -> assert issue.line_no == 4 end)

    code
    |> run(client_modules: [MyHttp], mock_wrappers: [])
    |> assert_issue(fn i -> assert i.line_no == 5 end)
  end

  test "resolves aliases and imports of client modules" do
    """
    defmodule ClientTest do
      use ExUnit.Case
      alias HTTPoison, as: H
      alias Mint.HTTP
      import Req, only: [get!: 2]

      test "a" do
        H.get!("https://example.com")
        HTTP.connect(:https, "example.com", 443)
        get!(req, url: "https://example.com")
        apply(HTTPoison, :post, ["https://example.com", ""])
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [8, 9, 10, 11] end)
  end

  test "an alias that shadows a client name is not the client" do
    """
    defmodule ClientTest do
      use ExUnit.Case
      alias MyApp.Req
      test "a", do: Req.get("https://example.com")
    end
    """
    |> run()
    |> refute_issues()
  end

  test "builders and configuration are not requests" do
    """
    defmodule ClientTest do
      use ExUnit.Case
      test "a" do
        req = Req.new(base_url: "https://example.com")
        client = Tesla.client([])
        request = Finch.build(:get, "https://example.com")
        Req.merge(req, retry: false)
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "with_mock bodies are mocked, local hosts are parsed rather than substring-matched" do
    """
    defmodule ClientTest do
      use ExUnit.Case
      test "a" do
        with_mock HTTPoison, [get: fn _ -> :ok end] do
          HTTPoison.get("https://example.com")
        end
      end
    end
    """
    |> run()
    |> refute_issues()

    """
    defmodule ClientTest do
      use ExUnit.Case
      test "a" do
        HTTPoison.get("https://notlocalhost.example.com/?next=localhost")
        HTTPoison.get("http://localhost.evil.com")
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert length(issues) == 2 end)

    """
    defmodule ClientTest do
      use ExUnit.Case
      test "a" do
        HTTPoison.get("http://localhost:\#{port}/x")
        HTTPoison.get("http://127.0.0.1/x")
        Req.get!("http://[::1]:4000/")
        :httpc.request(:get, {~c"http://localhost:4000", []}, [], [])
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "an imported client without an only list is recognised for common verbs" do
    """
    defmodule ClientTest do
      use ExUnit.Case
      import HTTPoison
      test "a", do: get!("https://example.com")
    end
    """
    |> run()
    |> assert_issue()
  end
end
