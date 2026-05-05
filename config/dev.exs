import Config

parse_http_ip = fn value ->
  parsed =
    value
    |> String.trim()
    |> String.split(".")
    |> Enum.map(fn octet ->
      case Integer.parse(octet) do
        {integer, ""} when integer >= 0 and integer <= 255 -> integer
        _ -> :error
      end
    end)

  case parsed do
    [a, b, c, d] when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) ->
      {a, b, c, d}

    _ ->
      raise """
      invalid BABS_HTTP_IP=#{inspect(value)}

      Use a dotted IPv4 address such as 127.0.0.1 or 0.0.0.0.
      """
  end
end

http_ip =
  case System.get_env("BABS_HTTP_IP") do
    nil -> {127, 0, 0, 1}
    value -> parse_http_ip.(value)
  end

http_port =
  case System.get_env("BABS_HTTP_PORT") || System.get_env("PORT") do
    nil -> 4000
    value -> String.to_integer(String.trim(value))
  end

config :babs, BabsWeb.Endpoint,
  http: [ip: http_ip, port: http_port],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  live_reload: [
    patterns: [
      ~r"apps/babs/lib/.*(ex)$"
    ]
  ],
  secret_key_base: String.duplicate("babs_dev_secret", 6)

config :phoenix, :plug_init_mode, :runtime
