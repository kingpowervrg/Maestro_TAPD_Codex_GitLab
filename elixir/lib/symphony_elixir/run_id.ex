defmodule SymphonyElixir.RunId do
  @moduledoc false

  @random_bytes 9

  @spec generate(String.t() | nil) :: String.t()
  def generate(issue_id \\ nil) do
    unique_component =
      @random_bytes
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    ["run", Integer.to_string(System.system_time(:microsecond)), unique_component]
    |> maybe_append_issue_id(issue_id)
    |> Enum.join("-")
  end

  defp maybe_append_issue_id(parts, issue_id) when is_binary(issue_id) and issue_id != "",
    do: parts ++ [issue_id]

  defp maybe_append_issue_id(parts, _issue_id), do: parts
end
