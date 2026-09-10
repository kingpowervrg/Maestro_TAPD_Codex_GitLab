defmodule SymphonyElixir.Tracker.Tapd.StoryBranch do
  @moduledoc false

  @branch_label_pattern ~r/(?:代码分支|开发分支|code\s+branch)\s*[:：]\s*(.+)/iu
  @html_fragment_pattern ~r/<[a-zA-Z][^>]*>/
  @forbidden_ref_chars ~r/[\x00-\x20\x7f~^:?*\[\\]/u

  @spec from_description(term()) :: String.t() | nil
  def from_description(description) when is_binary(description) do
    description
    |> description_lines()
    |> Enum.find_value(&branch_from_line/1)
  end

  def from_description(_description), do: nil

  defp description_lines(description) do
    if Regex.match?(@html_fragment_pattern, description) do
      case Floki.parse_fragment(description) do
        {:ok, nodes} ->
          block_lines =
            nodes
            |> Floki.find("p, div, li, td")
            |> Enum.map(&Floki.text(&1, sep: " "))

          [Floki.text(nodes, sep: "\n") | block_lines]
          |> Enum.flat_map(&String.split(&1, ~r/\R/u, trim: true))

        {:error, _reason} ->
          String.split(description, ~r/\R/u, trim: true)
      end
    else
      String.split(description, ~r/\R/u, trim: true)
    end
  end

  defp branch_from_line(line) do
    case Regex.run(@branch_label_pattern, line, capture: :all_but_first) do
      [raw_value] -> raw_value |> normalize_candidate() |> validate_candidate()
      _other -> nil
    end
  end

  defp normalize_candidate(raw_value) do
    raw_value
    |> String.trim()
    |> String.trim_leading("`")
    |> String.split(~r/\s/u, parts: 2)
    |> List.first()
    |> case do
      nil -> nil
      value -> value |> String.trim("`\"'") |> String.replace(~r/[，。；;,]+$/u, "")
    end
  end

  defp validate_candidate(nil), do: nil

  defp validate_candidate(candidate) do
    components = String.split(candidate, "/", trim: false)

    invalid? =
      candidate == "" or
        candidate == "@" or
        byte_size(candidate) > 255 or
        String.starts_with?(candidate, ["-", ".", "/"]) or
        String.ends_with?(candidate, [".", "/"]) or
        String.contains?(candidate, ["..", "@{"]) or
        Regex.match?(@forbidden_ref_chars, candidate) or
        Enum.any?(components, &invalid_component?/1)

    if invalid?, do: nil, else: candidate
  end

  defp invalid_component?(component) do
    component in ["", ".", ".."] or
      String.starts_with?(component, ".") or
      String.ends_with?(component, ".lock")
  end
end
