defmodule BabsWeb.GitDiffComponent do
  @moduledoc """
  Reusable function component for rendering workspace git status and diffs.
  """

  use Phoenix.Component

  attr :branch, :map, default: nil
  attr :status, :map, default: nil
  attr :diff, :map, default: nil
  attr :error, :any, default: nil

  def git_diff(assigns) do
    branch = Map.get(assigns, :branch)
    status = Map.get(assigns, :status)
    diff = Map.get(assigns, :diff)
    error = Map.get(assigns, :error)

    assigns =
      assigns
      |> assign(:branch_label, branch_label(branch))
      |> assign(:branch_detail, branch_detail(branch))
      |> assign(:status_label, status_label(status))
      |> assign(:status_class, status_class(status))
      |> assign(:status_text, status_text(status))
      |> assign(:diff_truncated?, truncated?(diff))
      |> assign(:files, diff_files(diff))
      |> assign(:error_title, error_title(error))
      |> assign(:error_detail, error_detail(error))

    ~H"""
    <section class="git-diff-panel" data-testid="git-diff-component">
      <header class="git-diff-head">
        <div>
          <h2><BabsWeb.Icon.icon name="git-branch" /> Workspace Diff</h2>
          <p>{@branch_detail}</p>
        </div>

        <div class="git-diff-meta" aria-label="Git summary">
          <span class="badge imported" data-testid="git-diff-branch">
            <BabsWeb.Icon.icon name="git-branch" /> {@branch_label}
          </span>
          <span class={@status_class} data-testid="git-diff-status">
            <span class="dot"></span>{@status_label}
          </span>
          <span :if={@diff_truncated?} class="badge queued" data-testid="git-diff-truncated">
            truncated
          </span>
        </div>
      </header>

      <div :if={@error} class="git-diff-message error" data-testid="git-diff-error">
        <BabsWeb.Icon.icon name="triangle-alert" />
        <div>
          <h3>{@error_title}</h3>
          <p>{@error_detail}</p>
        </div>
      </div>

      <div :if={!@error} class="git-diff-body">
        <pre :if={@status_text != ""} class="git-status-text" data-testid="git-diff-status-text"><%= @status_text %></pre>

        <div :if={@files == []} class="git-diff-message" data-testid="git-diff-empty">
          <BabsWeb.Icon.icon name="check" />
          <div>
            <h3>No changes</h3>
            <p>The workspace has no diff to review.</p>
          </div>
        </div>

        <div :if={@files != []} class="git-diff-files" data-testid="git-diff-files">
          <article
            :for={file <- @files}
            class="git-diff-file"
            data-testid={"git-diff-file-#{file.id}"}
          >
            <header class="git-diff-file-head">
              <strong>{file.path}</strong>
              <span>{file.additions} additions / {file.deletions} deletions</span>
            </header>

            <pre class="git-diff-code"><code
                :for={line <- file.lines}
                class={line_class(line.kind)}
                data-line-kind={line.kind}
              ><span class="git-line-prefix"><%= line.prefix %></span><span class="git-line-text"><%= line.text %></span></code></pre>
          </article>
        </div>
      </div>
    </section>
    """
  end

  defp branch_label(%{name: name}) when is_binary(name) and name != "", do: name
  defp branch_label(_branch), do: "unknown"

  defp branch_detail(%{detached?: true}), do: "Detached HEAD"
  defp branch_detail(_branch), do: "Current branch and workspace changes"

  defp status_label(%{clean?: true}), do: "clean"
  defp status_label(%{clean?: false}), do: "changed"
  defp status_label(_status), do: "unknown"

  defp status_class(%{clean?: true}), do: "badge captured"
  defp status_class(%{clean?: false}), do: "badge pending"
  defp status_class(_status), do: "badge"

  defp status_text(%{text: text}) when is_binary(text), do: String.trim_trailing(text)
  defp status_text(_status), do: ""

  defp truncated?(%{truncated?: true}), do: true
  defp truncated?(_result), do: false

  defp diff_files(diff) do
    diff
    |> diff_text()
    |> String.split("\n", trim: false)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce({[], nil}, &parse_diff_line/2)
    |> then(fn {files, current} -> flush_file(files, current) end)
    |> Enum.reverse()
  end

  defp diff_text(%{text: text}) when is_binary(text), do: trim_final_line_break(text)
  defp diff_text(_diff), do: ""

  defp trim_final_line_break(text) do
    cond do
      String.ends_with?(text, "\r\n") -> binary_part(text, 0, byte_size(text) - 2)
      String.ends_with?(text, "\n") -> binary_part(text, 0, byte_size(text) - 1)
      true -> text
    end
  end

  defp parse_diff_line(line, {files, current}) do
    case diff_file_path(line) do
      {:ok, path} ->
        file =
          path
          |> new_file()
          |> add_line(diff_line(line))

        {flush_file(files, current), file}

      :error ->
        file = current || new_file("Workspace diff")
        {files, add_line(file, diff_line(line))}
    end
  end

  defp diff_file_path("diff --git " <> rest) do
    case diff_header_path(rest) do
      {:ok, path} -> {:ok, path}
      :error -> {:ok, "Workspace diff"}
    end
  end

  defp diff_file_path(_line), do: :error

  defp diff_header_path(rest) do
    case Regex.run(~r/\Aa\/(.+) b\/(.+)\z/, rest) do
      [_all, _left, right] -> {:ok, normalize_path(right)}
      _no_match -> quoted_diff_header_path(rest)
    end
  end

  defp quoted_diff_header_path(rest) do
    with {:ok, _left, rest} <- quoted_git_path(rest),
         rest <- String.trim_leading(rest),
         {:ok, right, rest} <- quoted_git_path(rest),
         "" <- String.trim(rest) do
      {:ok, right |> strip_diff_prefix() |> normalize_path()}
    else
      _not_quoted -> :error
    end
  end

  defp quoted_git_path("\"" <> rest), do: quoted_git_path(rest, [])
  defp quoted_git_path(_rest), do: :error

  defp quoted_git_path("\"" <> rest, acc), do: {:ok, IO.iodata_to_binary(Enum.reverse(acc)), rest}
  defp quoted_git_path("\\" <> rest, acc), do: escaped_git_path(rest, acc)

  defp quoted_git_path(<<char::utf8, rest::binary>>, acc),
    do: quoted_git_path(rest, [<<char::utf8>> | acc])

  defp quoted_git_path(<<byte, rest::binary>>, acc), do: quoted_git_path(rest, [<<byte>> | acc])
  defp quoted_git_path("", _acc), do: :error

  defp escaped_git_path(<<digit, rest::binary>>, acc) when digit in ?0..?7 do
    {octal, rest} = octal_digits(rest, [digit], 2)
    {byte, ""} = Integer.parse(octal, 8)
    quoted_git_path(rest, [<<byte>> | acc])
  end

  defp escaped_git_path("\"" <> rest, acc), do: quoted_git_path(rest, ["\"" | acc])
  defp escaped_git_path("\\" <> rest, acc), do: quoted_git_path(rest, ["\\" | acc])
  defp escaped_git_path("a" <> rest, acc), do: quoted_git_path(rest, [<<7>> | acc])
  defp escaped_git_path("b" <> rest, acc), do: quoted_git_path(rest, [<<8>> | acc])
  defp escaped_git_path("f" <> rest, acc), do: quoted_git_path(rest, [<<12>> | acc])
  defp escaped_git_path("n" <> rest, acc), do: quoted_git_path(rest, ["\n" | acc])
  defp escaped_git_path("r" <> rest, acc), do: quoted_git_path(rest, ["\r" | acc])
  defp escaped_git_path("t" <> rest, acc), do: quoted_git_path(rest, ["\t" | acc])
  defp escaped_git_path("v" <> rest, acc), do: quoted_git_path(rest, [<<11>> | acc])

  defp escaped_git_path(<<char::utf8, rest::binary>>, acc),
    do: quoted_git_path(rest, [<<char::utf8>> | acc])

  defp escaped_git_path(<<byte, rest::binary>>, acc), do: quoted_git_path(rest, [<<byte>> | acc])
  defp escaped_git_path("", _acc), do: :error

  defp octal_digits(<<digit, rest::binary>>, digits, remaining)
       when remaining > 0 and digit in ?0..?7 do
    octal_digits(rest, [digit | digits], remaining - 1)
  end

  defp octal_digits(rest, digits, _remaining) do
    {digits |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp strip_diff_prefix("b/" <> path), do: path
  defp strip_diff_prefix("a/" <> path), do: path
  defp strip_diff_prefix(path), do: path

  defp normalize_path(path) do
    case :unicode.characters_to_binary(path, :utf8, :utf8) do
      normalized when is_binary(normalized) -> normalized
      {:error, valid, rest} -> valid <> "?" <> normalize_path(drop_first_byte(rest))
      {:incomplete, valid, _rest} -> valid <> "?"
    end
  end

  defp drop_first_byte(<<_byte, rest::binary>>), do: rest
  defp drop_first_byte(_rest), do: ""

  defp new_file(path) do
    %{path: path, id: test_id(path), additions: 0, deletions: 0, lines: []}
  end

  defp flush_file(files, nil), do: files
  defp flush_file(files, file), do: [Map.update!(file, :lines, &Enum.reverse/1) | files]

  defp add_line(file, line) do
    file
    |> Map.update!(:lines, &[line | &1])
    |> count_line(line.kind)
  end

  defp count_line(file, :addition), do: Map.update!(file, :additions, &(&1 + 1))
  defp count_line(file, :deletion), do: Map.update!(file, :deletions, &(&1 + 1))
  defp count_line(file, _kind), do: file

  defp diff_line("[TRUNCATED]"), do: %{kind: :truncated, prefix: "", text: "[TRUNCATED]"}
  defp diff_line("@@" <> _rest = line), do: %{kind: :hunk, prefix: "", text: line}
  defp diff_line("+++" <> _rest = line), do: %{kind: :header, prefix: "", text: line}
  defp diff_line("---" <> _rest = line), do: %{kind: :header, prefix: "", text: line}
  defp diff_line("+" <> text), do: %{kind: :addition, prefix: "+", text: text}
  defp diff_line("-" <> text), do: %{kind: :deletion, prefix: "-", text: text}
  defp diff_line(" " <> text), do: %{kind: :context, prefix: " ", text: text}
  defp diff_line(line), do: %{kind: :context, prefix: " ", text: line}

  defp line_class(kind), do: "git-diff-line #{kind}"

  defp test_id(path) do
    path
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "workspace"
      id -> id
    end
  end

  defp error_title(nil), do: nil
  defp error_title({:not_git_repo, _details}), do: "Workspace is not a git repository"
  defp error_title({:invalid_workspace, _details}), do: "Workspace is unavailable"
  defp error_title({:no_assignee, _ticket_id}), do: "Ticket has no assignee"
  defp error_title({:no_cwd, _slug}), do: "Assignee has no workspace"
  defp error_title({:citizen_not_found, _slug}), do: "Assignee was not found"
  defp error_title(_reason), do: "Git diff is unavailable"

  defp error_detail(nil), do: nil

  defp error_detail({:not_git_repo, %{workspace: workspace}}),
    do: "#{workspace} is not a git repository."

  defp error_detail({:invalid_workspace, %{workspace: workspace}}),
    do: "#{workspace} is not a readable workspace."

  defp error_detail({:no_assignee, ticket_id}), do: "#{ticket_id} is not assigned to a Citizen."
  defp error_detail({:no_cwd, slug}), do: "#{slug} does not have a configured cwd."
  defp error_detail({:citizen_not_found, slug}), do: "#{slug} is not in the Citizen catalog."
  defp error_detail(reason), do: inspect(reason)
end
