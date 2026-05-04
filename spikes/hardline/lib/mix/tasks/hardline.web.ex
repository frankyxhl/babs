defmodule Mix.Tasks.Hardline.Web do
  @moduledoc """
  Starts the manual Phase 0 Channel -> xterm.js validation page.

      mix hardline.web --port 4010
      mix hardline.web --host 100.x.y.z --port 4010
  """

  use Mix.Task

  @shortdoc "Starts the Hardline xterm.js validation page"

  @impl true
  def run(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          host: :string,
          port: :integer,
          name: :string,
          session: :string,
          prefix: :string,
          command: :string
        ]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    Mix.Task.run("app.start")

    port = Keyword.get(opts, :port, 4010)
    host = Keyword.get(opts, :host, "127.0.0.1")
    ip = parse_ip!(host)
    prefix = Keyword.get(opts, :prefix, Hardline.Runner.managed_prefix())
    command = Keyword.get(opts, :command, Hardline.Runner.default_shell_command())

    Application.put_env(:hardline, Hardline.Web.Endpoint,
      adapter: Bandit.PhoenixAdapter,
      http: [ip: ip, port: port],
      url: [scheme: "http", host: host, port: port],
      check_origin: :conn,
      server: true,
      secret_key_base: String.duplicate("a", 64),
      pubsub_server: Hardline.PubSub
    )

    {:ok, _manager} =
      Hardline.Web.Manager.start_link(prefix: prefix, command: command)

    {:ok, _endpoint} = Hardline.Web.Endpoint.start_link()

    Mix.shell().info("Hardline web validation running at http://#{host}:#{port}/")
    Mix.shell().info("Managed tmux prefix: #{prefix}-")
    Mix.shell().info("Default command: #{command}")
    Mix.shell().info("Leave this process running for the browser Hardline manager console.")

    Process.sleep(:infinity)
  end

  defp parse_ip!(host) do
    host
    |> String.to_charlist()
    |> :inet.parse_address()
    |> case do
      {:ok, ip} -> ip
      {:error, :einval} -> Mix.raise("host must be an IPv4/IPv6 address, got #{inspect(host)}")
    end
  end
end
