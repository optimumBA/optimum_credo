defmodule OptimumCredo.Check.Warning.HttpClientInTest do
  @moduledoc """
  Finds calls to HTTP client modules in test files.

  Receivers are resolved through the `alias`es in lexical scope (`alias HTTPoison, as: H`)
  and `import`s of a client module (`import Req` then `get!(..)`), and `apply(Req, :get, ..)`
  is recognised. Setup-style calls (`Req.new`, `Tesla.client`, `Finch.build`, ...) are not
  requests (`non_request_functions`). Calls are accepted when they appear inside a mock
  wrapper (`expect`, `stub`, `mock`, `with_mock`, ... including remote forms like
  `Bypass.expect/3`), when a `plug:` option routes the request to a test plug, or when a
  literal URL points at `localhost`/`127.0.0.1`/`::1`/`0.0.0.0` (the host is parsed, so
  `https://notlocalhost.example` does not qualify). Static heuristic: clients reached
  through your own wrapper module, or through a client built elsewhere, are not seen.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [
      client_modules: [
        HTTPoison,
        HTTPotion,
        Req,
        Tesla,
        Finch,
        Mojito,
        Mint.HTTP,
        :httpc,
        :hackney
      ],
      mock_wrappers: [
        :expect,
        :expect_once,
        :stub,
        :stub_with,
        :mock,
        :mock_global,
        :with_mock,
        :with_mocks
      ],
      non_request_functions: [
        :new,
        :build,
        :client,
        :build_client,
        :start,
        :start_link,
        :child_spec,
        :merge,
        :update,
        :attach,
        :put_header,
        :put_headers,
        :put_option,
        :put_private
      ],
      allow_local_urls: true
    ],
    explanations: [
      check: """
      Tests must not hit the network. Stub external services with Mox, Bypass, `Req.Test`
      or fixtures.

      Bad:   HTTPoison.get!("https://example.com/api")
      Good:  Mox.expect(HttpMock, :get, fn _ -> {:ok, response} end)
      """,
      params: [
        client_modules: "HTTP client modules (atoms or strings) whose remote calls are reported.",
        mock_wrappers: "Call names whose arguments are treated as mock definitions and skipped.",
        non_request_functions:
          "Client functions that build or configure but never send a request.",
        allow_local_urls:
          "Accept calls whose literal URL points at localhost or a loopback address."
      ]
    ]

  alias OptimumCredo.TestsSupport

  # Names assumed for an imported client module whose compiled exports are unavailable (neither loaded nor installed).
  @assumed_imports ~w(get get! post post! put put! patch patch! delete delete! head head! options options! request request! run run!)a
  @local_url "^[a-z][a-z0-9+.\\-]*://(localhost|127\\.0\\.0\\.1|\\[::1\\]|0\\.0\\.0\\.0)([:/?#]|$)"

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    if TestsSupport.test_file?(source_file) do
      issue_meta = IssueMeta.for(source_file, params)

      config = %{
        clients:
          params
          |> Params.get(:client_modules, __MODULE__)
          |> Enum.map(&TestsSupport.normalize_module/1),
        wrappers: Params.get(params, :mock_wrappers, __MODULE__),
        non_requests: Params.get(params, :non_request_functions, __MODULE__),
        local?: Params.get(params, :allow_local_urls, __MODULE__)
      }

      source_file
      |> TestsSupport.ast()
      |> TestsSupport.walk_env([], fn node, env, acc -> visit(node, env, acc, config) end)
      |> Enum.reverse()
      |> Enum.map(fn {client, fun, line} ->
        format_issue(issue_meta,
          message: "#{client}.#{fun} may hit the network in a test; stub it instead.",
          line_no: line,
          trigger: to_string(fun)
        )
      end)
    else
      []
    end
  end

  defp visit(node, env, acc, config) do
    call = TestsSupport.call(node, env)

    cond do
      call == nil -> {:cont, acc}
      call.fun in config.wrappers -> {:skip, acc}
      true -> report(call, env, acc, config)
    end
  end

  defp report(call, env, acc, config) do
    with client when client != nil <- client(call, env, config),
         false <- call.fun in config.non_requests,
         false <- exempt?(call.args, config.local?) do
      {:cont, [{client, call.fun, call.meta[:line] || 1} | acc]}
    else
      _other -> {:cont, acc}
    end
  end

  defp client(%{module: module} = call, env, config) do
    cond do
      module in config.clients -> module
      call.kind == :local and module == nil -> imported_client(call, env, config)
      true -> nil
    end
  end

  defp imported_client(call, env, config) do
    arities = [length(call.args), length(call.args) + 1]

    Enum.find_value(env.imports, fn spec ->
      if spec.module in config.clients and
           TestsSupport.provides?(spec, call.fun, arities, @assumed_imports),
         do: spec.module
    end)
  end

  defp exempt?(args, local?) do
    plug? =
      Enum.any?(args, fn
        options when is_list(options) ->
          Keyword.keyword?(options) and Keyword.has_key?(options, :plug)

        _ignored ->
          false
      end)

    plug? or (local? and Enum.any?(args, &local_url?/1))
  end

  defp local_url?(arg) do
    TestsSupport.walk(arg, false, fn
      text, acc when is_binary(text) -> acc or Regex.match?(Regex.compile!(@local_url, "i"), text)
      _node, acc -> acc
    end)
  end
end
