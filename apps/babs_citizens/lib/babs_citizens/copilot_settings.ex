defmodule Babs.Citizens.CopilotSettings do
  @moduledoc """
  Minimal helpers for Copilot CLI settings used by Babs-owned Citizens.
  """

  @config_file "config.json"
  @default_header """
  // User settings belong in settings.json.
  // This file is managed automatically.
  """

  def trust_folder(cwd, opts \\ []) when is_binary(cwd) do
    home = opts |> Keyword.get(:home, default_home()) |> Path.expand()
    settings_path = Path.join(home, @config_file)
    folder = Path.expand(cwd)

    with :ok <- ensure_settings_dir(settings_path),
         {:ok, {settings, header}} <- read_settings(settings_path),
         {:ok, updated} <- put_trusted_folder(settings, settings_path, folder),
         :ok <- write_settings(settings_path, updated, header) do
      :ok
    end
  end

  defp ensure_settings_dir(settings_path) do
    case File.mkdir_p(Path.dirname(settings_path)) do
      :ok -> :ok
      {:error, reason} -> {:error, {:copilot_settings_dir_failed, settings_path, reason}}
    end
  end

  defp read_settings(settings_path) do
    case File.read(settings_path) do
      {:ok, content} ->
        with {:ok, settings} <- decode_settings(settings_path, content) do
          {:ok, {settings, leading_comment_header(content)}}
        end

      {:error, :enoent} ->
        {:ok, {%{}, @default_header}}

      {:error, reason} ->
        {:error, {:copilot_settings_read_failed, settings_path, reason}}
    end
  end

  defp decode_settings(_settings_path, content) when content in ["", "\n"], do: {:ok, %{}}

  defp decode_settings(settings_path, content) do
    stripped = strip_full_line_comments(content)

    case Jason.decode(stripped) do
      {:ok, settings} when is_map(settings) ->
        {:ok, settings}

      {:ok, _other} ->
        {:error, {:copilot_settings_invalid, settings_path}}

      {:error, reason} ->
        {:error, {:copilot_settings_decode_failed, settings_path, Exception.message(reason)}}
    end
  end

  defp put_trusted_folder(settings, settings_path, folder) do
    case Map.get(settings, "trustedFolders", []) do
      folders when is_list(folders) ->
        if Enum.all?(folders, &is_binary/1) do
          {:ok, Map.put(settings, "trustedFolders", append_once(folders, folder))}
        else
          {:error, {:copilot_trusted_folders_invalid, settings_path}}
        end

      _other ->
        {:error, {:copilot_trusted_folders_invalid, settings_path}}
    end
  end

  defp append_once(values, value) do
    if value in values, do: values, else: values ++ [value]
  end

  defp write_settings(settings_path, settings, header) do
    with {:ok, encoded} <- encode_settings(settings) do
      write_if_changed(settings_path, header <> encoded <> "\n")
    end
  end

  defp encode_settings(settings) do
    case Jason.encode(settings, pretty: true) do
      {:ok, encoded} -> {:ok, encoded}
      {:error, reason} -> {:error, {:copilot_settings_encode_failed, Exception.message(reason)}}
    end
  end

  defp write_if_changed(settings_path, content) do
    case File.read(settings_path) do
      {:ok, ^content} ->
        :ok

      _other ->
        case File.write(settings_path, content) do
          :ok -> :ok
          {:error, reason} -> {:error, {:copilot_settings_write_failed, settings_path, reason}}
        end
    end
  end

  defp default_home do
    System.get_env("COPILOT_HOME") || Path.join(System.user_home!(), ".copilot")
  end

  defp strip_full_line_comments(content) do
    content
    |> String.split("\n", trim: false)
    |> Enum.reject(fn line -> line |> String.trim_leading() |> String.starts_with?("//") end)
    |> Enum.join("\n")
  end

  defp leading_comment_header(content) do
    header =
      content
      |> String.split("\n", trim: false)
      |> Enum.take_while(fn line ->
        trimmed = String.trim(line)
        trimmed == "" or String.starts_with?(trimmed, "//")
      end)

    if Enum.any?(header, fn line -> line |> String.trim() |> String.starts_with?("//") end) do
      Enum.join(header, "\n") |> String.trim_trailing() |> Kernel.<>("\n")
    else
      @default_header
    end
  end
end
