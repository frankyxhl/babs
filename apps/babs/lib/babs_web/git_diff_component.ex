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

  defp diff_text(%{text: text}) when is_binary(text), do: String.trim_trailing(text)
  defp diff_text(_diff), do: ""

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
    case Regex.run(~r/\Aa\/(.+) b\/(.+)\z/, rest) do
      [_all, _left, right] -> {:ok, right}
      _no_match -> {:ok, "Workspace diff"}
    end
  end

  defp diff_file_path(_line), do: :error

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
