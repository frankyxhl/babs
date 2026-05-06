defmodule Babs.Citizens.TmuxInventory do
  @moduledoc """
  Read-only tmux pane inventory for explicit imported Hardline attach.
  """

  alias Babs.Citizens.{ImportedHardline, Runner}

  @format Enum.join(
            [
              "\#{session_name}",
              "\#{window_index}",
              "\#{window_name}",
              "\#{pane_index}",
              "\#{pane_id}",
              "\#{pane_current_command}",
              "\#{pane_current_path}",
              "\#{session_attached}"
            ],
            "\t"
          )

  def list_panes(opts \\ []) do
    case list_panes_result(opts) do
      {:ok, panes} -> panes
      {:error, _reason} -> []
    end
  end

  def list_panes_result(opts \\ []) do
    tmux = Keyword.get(opts, :tmux, &tmux_cmd/1)

    case tmux.(["list-panes", "-a", "-F", @format]) do
      {:ok, {output, 0}} -> {:ok, parse_panes(output)}
      {:ok, {output, status}} -> {:error, {:tmux_list_panes_failed, status, output}}
      {:error, reason} -> {:error, reason}
    end
  end

  def parse_panes(output) when is_binary(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&parse_pane_line/1)
  end

  def classify_panes(panes, records) when is_list(panes) and is_list(records) do
    imported_ids =
      records
      |> Enum.filter(&ImportedHardline.external?/1)
      |> Enum.flat_map(fn record ->
        [ImportedHardline.pane_id(record), ImportedHardline.target(record)]
      end)
      |> Enum.reject(&blank?/1)
      |> MapSet.new()

    Enum.map(panes, fn pane ->
      Map.put(pane, :classification, classify_pane(pane, imported_ids))
    end)
  end

  def candidates(records, opts \\ []) when is_list(records) do
    opts
    |> list_panes()
    |> classify_panes(records)
  end

  def attachable_panes(records, opts \\ []) when is_list(records) do
    records
    |> candidates(opts)
    |> Enum.filter(&(&1.classification == :attachable))
  end

  def find_attachable(target, records, opts \\ []) when is_binary(target) and is_list(records) do
    records
    |> attachable_panes(opts)
    |> Enum.find(&target_match?(&1, target))
    |> case do
      nil -> {:error, :tmux_pane_not_attachable}
      pane -> {:ok, pane}
    end
  end

  def target_exists?(target, opts \\ []) when is_binary(target) do
    opts
    |> list_panes()
    |> Enum.any?(&target_match?(&1, target))
  end

  def target_match?(pane, target) when is_map(pane) and is_binary(target) do
    target in [
      Map.get(pane, :target),
      Map.get(pane, :pane_id),
      Map.get(pane, :session_name)
    ]
  end

  defp parse_pane_line(line) do
    case String.split(line, "\t", parts: 8) do
      [
        session_name,
        window_index,
        window_name,
        pane_index,
        pane_id,
        current_command,
        current_path,
        attached
      ] ->
        [
          %{
            session_name: session_name,
            window_index: window_index,
            window_name: window_name,
            pane_index: pane_index,
            pane_id: pane_id,
            target: "#{session_name}:#{window_index}.#{pane_index}",
            current_command: current_command,
            current_path: current_path,
            attached?: attached == "1"
          }
        ]

      _invalid ->
        []
    end
  end

  defp classify_pane(pane, imported_ids) do
    cond do
      Runner.managed_session?(pane.session_name) ->
        :babs_owned

      MapSet.member?(imported_ids, pane.pane_id) or MapSet.member?(imported_ids, pane.target) ->
        :imported

      true ->
        :attachable
    end
  end

  defp tmux_cmd(args) do
    tmux = tmux_binary()
    {:ok, System.cmd(tmux, args, stderr_to_stdout: true)}
  rescue
    error in ErlangError ->
      if error.original == :enoent do
        {:error, {:tmux_executable_not_found, tmux_binary()}}
      else
        reraise(error, __STACKTRACE__)
      end
  end

  defp tmux_binary do
    :babs_citizens
    |> Application.get_env(Runner, [])
    |> Keyword.get(:tmux_binary, "tmux")
  end

  defp blank?(value), do: value in [nil, ""]
end
