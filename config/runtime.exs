import Config

babs_root =
  (System.get_env("BABS_ROOT") || System.get_env("RELEASE_ROOT") || File.cwd!())
  |> Path.expand()

config :babs_citizens, root: babs_root
config :babs, Babs.DevReloader, root: babs_root

if config_env() == :prod do
  config :babs, BabsWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE")
end
