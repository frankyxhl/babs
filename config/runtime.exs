import Config

babs_root =
  (System.get_env("BABS_ROOT") || System.get_env("RELEASE_ROOT") || File.cwd!())
  |> Path.expand()

non_empty_env = fn name ->
  case System.get_env(name) do
    nil ->
      nil

    value ->
      value = String.trim(value)
      if value == "", do: nil, else: value
  end
end

socket_auth_token = non_empty_env.("BABS_SOCKET_TOKEN")
workspace_root = non_empty_env.("BABS_WORKSPACE_ROOT")
tickets_root = non_empty_env.("BABS_TICKETS_ROOT")
knowledge_root = non_empty_env.("BABS_KNOWLEDGE_ROOT")
federation_config_path = non_empty_env.("BABS_FEDERATION_CONFIG")

citizens_db_path =
  case non_empty_env.("BABS_CITIZENS_DB_PATH") do
    nil ->
      if config_env() == :test do
        test_partition = non_empty_env.("MIX_TEST_PARTITION")

        test_db_name =
          if test_partition do
            "babs_citizens_#{test_partition}.sqlite3"
          else
            "babs_citizens.sqlite3"
          end

        Path.join([babs_root, "tmp", "test", test_db_name])
      else
        Path.join([babs_root, "var", "babs_citizens.sqlite3"])
      end

    path ->
      Path.expand(path, babs_root)
  end

ensure_owner_only = fn path, mode ->
  case File.chmod(path, mode) do
    :ok -> :ok
    {:error, _reason} -> :ok
  end
end

citizens_db_dir = Path.dirname(citizens_db_path)
File.mkdir_p!(citizens_db_dir)
ensure_owner_only.(citizens_db_dir, 0o700)

unless File.exists?(citizens_db_path) do
  File.touch!(citizens_db_path)
end

ensure_owner_only.(citizens_db_path, 0o600)

if config_env() == :prod and is_nil(socket_auth_token) do
  raise """
  missing BABS_SOCKET_TOKEN

  Production browser terminals require a shared socket token. Set
  BABS_SOCKET_TOKEN and open terminal pages with ?socket_token=<token>.
  """
end

citizens_config = [root: babs_root]

citizens_config =
  if workspace_root do
    Keyword.put(citizens_config, :workspace_root, Path.expand(workspace_root, babs_root))
  else
    citizens_config
  end

citizens_config =
  if tickets_root do
    Keyword.put(citizens_config, :tickets_root, Path.expand(tickets_root, babs_root))
  else
    citizens_config
  end

citizens_config =
  if knowledge_root do
    Keyword.put(citizens_config, :knowledge_root, Path.expand(knowledge_root, babs_root))
  else
    citizens_config
  end

citizens_config =
  if federation_config_path do
    Keyword.put(
      citizens_config,
      :federation_config_path,
      Path.expand(federation_config_path, babs_root)
    )
  else
    citizens_config
  end

config :babs_citizens, citizens_config

# Citizen-to-Citizen auto-reply gate. OFF unless BABS_CITIZEN_AUTO_REPLY=1.
# When enabled, a comment replying to / @mentioning a Citizen wakes it to
# respond, bounded per thread by BABS_CITIZEN_AUTO_REPLY_BUDGET (default 6).
config :babs_citizens,
       :citizen_auto_reply_enabled,
       non_empty_env.("BABS_CITIZEN_AUTO_REPLY") == "1"

case non_empty_env.("BABS_CITIZEN_AUTO_REPLY_BUDGET") do
  nil -> :ok
  value -> config :babs_citizens, :citizen_auto_reply_budget, String.to_integer(value)
end

if config_env() != :prod and non_empty_env.("BABS_BDD_FAKE_DIRECT") == "1" do
  config :babs_citizens, :ticket_runtime_opts,
    adapter: Babs.Citizens.DirectCli.Adapters.Fake,
    executor: fn command ->
      reply = System.get_env("BABS_BDD_DIRECT_REPLY") || "BDD direct CLI UI reply."
      session_id = command.provider_session_id || "bdd-direct-ui-session"
      prompt_capture_path = non_empty_env.("BABS_BDD_DIRECT_PROMPTS_PATH")

      if prompt_capture_path do
        File.mkdir_p!(Path.dirname(prompt_capture_path))

        prompt =
          command.args
          |> List.last()
          |> case do
            value when is_binary(value) -> value
            _other -> command.stdin || ""
          end

        File.write!(
          prompt_capture_path,
          Jason.encode!(%{
            "provider" => command.provider,
            "provider_session_id" => command.provider_session_id,
            "resume" => Map.get(command, :resume?, false),
            "prompt" => prompt
          }) <> "\n",
          [:append]
        )
      end

      {:ok,
       %{stdout: Jason.encode!(%{"session_id" => session_id, "content" => reply}), stderr: ""}}
    end
end

config :babs, Babs.DevReloader, root: babs_root
config :babs, BabsWeb.UserSocket, auth_token: socket_auth_token

config :babs_citizens, Babs.Citizens.Repo,
  database: citizens_db_path,
  pool_size: if(config_env() == :test, do: 1, else: 5)

if config_env() == :prod do
  phx_host = non_empty_env.("PHX_HOST")

  if is_nil(phx_host) do
    raise """
    missing PHX_HOST

    Production browser terminals require the externally reachable host so
    Phoenix can accept websocket origins. Set PHX_HOST to the domain or IP
    used in the browser.
    """
  end

  integer_env = fn names, default ->
    names
    |> Enum.map(non_empty_env)
    |> Enum.find(& &1)
    |> case do
      nil -> default
      value -> String.to_integer(value)
    end
  end

  http_port = integer_env.(["PORT"], 4000)
  url_port = integer_env.(["PHX_URL_PORT", "PHX_PORT", "PORT"], http_port)
  phx_scheme = non_empty_env.("PHX_SCHEME") || "http"

  config :babs, BabsWeb.Endpoint,
    server: true,
    url: [scheme: phx_scheme, host: phx_host, port: url_port],
    http: [ip: {0, 0, 0, 0}, port: http_port],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE")
end
