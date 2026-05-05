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
  config :babs, BabsWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE")
end
