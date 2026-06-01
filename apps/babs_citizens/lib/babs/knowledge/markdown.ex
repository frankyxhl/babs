defmodule Babs.Knowledge.Markdown do
  @moduledoc """
  Parses generic Knowledge markdown frontmatter and renders sanitized HTML.

  Frontmatter is decoded as a generic string-keyed map. Callers that need
  specific required or optional fields should validate that schema after parse.
  """

  @mdex_extensions [
    strikethrough: true,
    table: true,
    # Keep GitHub task markers parsed before sanitization. MDEx's default
    # sanitizer strips checkbox input tags, so returned HTML stays non-interactive.
    tasklist: true,
    autolink: true
  ]
  @max_frontmatter_bytes 65_536

  @spec parse(term()) :: {:ok, {map(), String.t()}} | {:error, term()}
  def parse(content) when is_binary(content) do
    case split_frontmatter(content) do
      {:ok, yaml, body} ->
        with {:ok, frontmatter} <- decode_frontmatter(yaml) do
          {:ok, {frontmatter, body}}
        end

      :no_frontmatter ->
        {:ok, {%{}, content}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def parse(_content), do: {:error, {:invalid_markdown, :not_string}}

  @spec render_body(term()) :: {:ok, String.t()} | {:error, term()}
  def render_body("") do
    {:ok, ""}
  end

  def render_body(body) when is_binary(body) do
    case MDEx.to_html(body, mdex_options()) do
      {:ok, html} -> {:ok, html}
      {:error, reason} -> {:error, {:render_failed, reason}}
    end
  rescue
    error -> {:error, {:render_failed, {error.__struct__, Exception.message(error)}}}
  end

  def render_body(_body), do: {:error, {:invalid_markdown, :not_string}}

  @spec render(term()) ::
          {:ok, %{frontmatter: map(), body: String.t(), html: String.t()}} | {:error, term()}
  def render(content) do
    with {:ok, {frontmatter, body}} <- parse(content),
         {:ok, html} <- render_body(body) do
      {:ok, %{frontmatter: frontmatter, body: body, html: html}}
    end
  end

  defp split_frontmatter(content) do
    case take_line(content) do
      {:ok, line, _raw_line, rest} ->
        if fence_line?(line) do
          find_closing_fence(rest, [], 0)
        else
          :no_frontmatter
        end

      :eof ->
        :no_frontmatter
    end
  end

  defp find_closing_fence("", _yaml_lines, _byte_count),
    do: {:error, {:invalid_frontmatter, :missing_closing_fence}}

  defp find_closing_fence(content, yaml_lines, byte_count) do
    case take_line(content) do
      {:ok, line, raw_line, rest} ->
        if fence_line?(line) do
          {:ok, yaml_lines |> Enum.reverse() |> IO.iodata_to_binary(), rest}
        else
          byte_count = byte_count + byte_size(raw_line)

          if byte_count > @max_frontmatter_bytes do
            {:error, {:invalid_frontmatter, :frontmatter_too_large}}
          else
            find_closing_fence(rest, [raw_line | yaml_lines], byte_count)
          end
        end

      :eof ->
        {:error, {:invalid_frontmatter, :missing_closing_fence}}
    end
  end

  defp take_line(""), do: :eof

  defp take_line(content) do
    case :binary.match(content, "\n") do
      {index, 1} ->
        line = binary_part(content, 0, index)
        raw_line = binary_part(content, 0, index + 1)
        rest_start = index + 1
        rest = binary_part(content, rest_start, byte_size(content) - rest_start)
        {:ok, trim_trailing_bytes(line, [?\r]), raw_line, rest}

      :nomatch ->
        {:ok, trim_trailing_bytes(content, [?\r]), content, ""}
    end
  end

  defp fence_line?(line), do: trim_trailing_bytes(line, [?\s, ?\t, ?\r]) == "---"

  defp trim_trailing_bytes("", _bytes), do: ""

  defp trim_trailing_bytes(binary, bytes) do
    if :binary.last(binary) in bytes do
      binary
      |> binary_part(0, byte_size(binary) - 1)
      |> trim_trailing_bytes(bytes)
    else
      binary
    end
  end

  defp decode_frontmatter(yaml) do
    if String.trim(yaml) == "" do
      {:ok, %{}}
    else
      case YamlElixir.read_from_string(yaml, atoms: false) do
        {:ok, nil} -> {:ok, %{}}
        {:ok, frontmatter} when is_map(frontmatter) -> {:ok, frontmatter}
        {:ok, _value} -> {:error, {:invalid_frontmatter, :frontmatter_not_map}}
        {:error, reason} -> {:error, {:invalid_frontmatter, {:yaml_decode_failed, reason}}}
      end
    end
  rescue
    error ->
      {:error,
       {:invalid_frontmatter, {:yaml_decode_failed, {error.__struct__, Exception.message(error)}}}}
  end

  defp mdex_options do
    [
      extension: @mdex_extensions,
      # Raw HTML must reach MDEx's sanitizer; the sanitizer output is the boundary.
      render: [unsafe: true],
      sanitize: MDEx.Document.default_sanitize_options()
    ]
  end
end
