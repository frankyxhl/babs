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

if config_env() == :prod and is_nil(socket_auth_token) do
  raise """
  missing BABS_SOCKET_TOKEN

  Production browser terminals require a shared socket token. Set
  BABS_SOCKET_TOKEN and open terminal pages with ?socket_token=<token>.
  """
end

if workspace_root do
  config :babs_citizens, root: babs_root, workspace_root: workspace_root
else
  config :babs_citizens, root: babs_root
end

config :babs, Babs.DevReloader, root: babs_root
config :babs, BabsWeb.UserSocket, auth_token: socket_auth_token

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
