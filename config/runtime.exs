import Config

babs_root =
  (System.get_env("BABS_ROOT") || System.get_env("RELEASE_ROOT") || File.cwd!())
  |> Path.expand()

socket_auth_token = System.get_env("BABS_SOCKET_TOKEN")

if config_env() == :prod and socket_auth_token in [nil, ""] do
  raise """
  missing BABS_SOCKET_TOKEN

  Production browser terminals require a shared socket token. Set
  BABS_SOCKET_TOKEN and open terminal pages with ?socket_token=<token>.
  """
end

config :babs_citizens, root: babs_root
config :babs, Babs.DevReloader, root: babs_root
config :babs, BabsWeb.UserSocket, auth_token: socket_auth_token

if config_env() == :prod do
  phx_host = System.get_env("PHX_HOST")

  if phx_host in [nil, ""] do
    raise """
    missing PHX_HOST

    Production browser terminals require the externally reachable host so
    Phoenix can accept websocket origins. Set PHX_HOST to the domain or IP
    used in the browser.
    """
  end

  integer_env = fn names, default ->
    names
    |> Enum.map(&System.get_env/1)
    |> Enum.find(&(&1 not in [nil, ""]))
    |> case do
      nil -> default
      value -> String.to_integer(value)
    end
  end

  http_port = integer_env.(["PORT"], 4000)
  url_port = integer_env.(["PHX_URL_PORT", "PHX_PORT", "PORT"], http_port)
  phx_scheme = System.get_env("PHX_SCHEME") || "http"

  config :babs, BabsWeb.Endpoint,
    server: true,
    url: [scheme: phx_scheme, host: phx_host, port: url_port],
    http: [ip: {0, 0, 0, 0}, port: http_port],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE")
end
