defmodule MaestroTapdGitlabLite.Tracker.WorkpadCompletion do
  @moduledoc "Validates the final Lite workpad before the AI workflow field is written."

  @checklists ["Plan", "Acceptance Criteria", "Validation"]
  @handoff_fields ~w(repository branch_name commit_sha published_head_sha suggested_mr_title suggested_mr_description)

  @spec validate(term()) :: :ok | {:error, {:invalid_arguments, String.t()}}
  def validate(body) when is_binary(body) do
    sections = sections(body)

    with :ok <- validate_checklists(sections),
         :ok <- validate_confusions(sections),
         :ok <- validate_handoff(Map.get(sections, "Git Handoff", "")) do
      :ok
    end
  end

  def validate(_body), do: invalid("Final workpad body is required.")

  defp sections(body) do
    body
    |> String.split(~r/^\#{3}[ \t]+/m)
    |> Enum.drop(1)
    |> Enum.reduce(%{}, fn section, acc ->
      [title | lines] = String.split(section, "\n")
      # Duplicate sections cannot hide an unfinished checklist or placeholder.
      Map.update(acc, String.trim(title), Enum.join(lines, "\n"), &(&1 <> "\n" <> Enum.join(lines, "\n")))
    end)
  end

  defp validate_checklists(sections) do
    Enum.reduce_while(@checklists, :ok, fn title, :ok ->
      text = Map.get(sections, title, "")

      if Regex.match?(~r/^\s*[-*] \[[xX]\]/m, text) and not unchecked?(text) do
        {:cont, :ok}
      else
        {:halt, invalid("#{title} must contain completed checklist items and no unchecked items.")}
      end
    end)
  end

  defp validate_confusions(sections) do
    if unchecked?(Map.get(sections, "Confusions", "")),
      do: invalid("Resolve unchecked Confusions before completing the AI workflow."),
      else: :ok
  end

  defp unchecked?(text), do: Regex.match?(~r/^\s*[-*] \[[ \t]*\]/m, text)

  defp validate_handoff(text) do
    fields =
      Enum.map(@handoff_fields, fn key ->
        values = Regex.scan(~r/^\s*[-*] `?#{key}`?:[ \t]*(.+)$/m, text, capture: :all_but_first)

        value =
          case values do
            [[value]] -> value |> String.trim() |> String.trim("`") |> String.trim()
            _ -> ""
          end

        {key, value}
      end)
      |> Map.new()

    missing = Enum.filter(@handoff_fields, &placeholder?(fields[&1]))

    cond do
      missing != [] ->
        invalid("Git Handoff requires concrete values for: #{Enum.join(missing, ", ")}.")

      not valid_sha?(fields["commit_sha"]) or not valid_sha?(fields["published_head_sha"]) ->
        invalid("Git Handoff commit_sha and published_head_sha must be full commit SHAs.")

      String.downcase(fields["commit_sha"]) != String.downcase(fields["published_head_sha"]) ->
        invalid("Git Handoff published_head_sha must equal commit_sha after verified push.")

      String.contains?(fields["branch_name"], [" ", "\t", "..", "~", "^", ":", "?", "*", "[", "\\"]) ->
        invalid("Git Handoff branch_name must be a working branch name.")

      true ->
        :ok
    end
  end

  defp placeholder?(value), do: String.downcase(value) in ["", "pending", "tbd", "todo", "none", "n/a", "null", "unknown", "待定", "待填写"]
  defp valid_sha?(value), do: Regex.match?(~r/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/i, value)
  defp invalid(message), do: {:error, {:invalid_arguments, "Final workpad is incomplete: " <> message}}
end
