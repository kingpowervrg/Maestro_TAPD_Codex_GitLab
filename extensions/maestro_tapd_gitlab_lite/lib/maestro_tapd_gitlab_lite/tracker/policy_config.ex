defmodule MaestroTapdGitlabLite.Tracker.PolicyConfig do
  @moduledoc "Configuration projection for company-owned TAPD fields and values."

  @default_active_states ["new", "reopened"]
  @default_task_active_states ["status_4", "status_10"]
  @default_accepted_value "接受/处理"
  @default_resolved_value "AI已解决"
  @default_exception_value "AI异常"
  @default_model_level "medium"
  @supported_model_levels ~w(low medium high xhigh)
  @story_field_aliases %{
    "custom_field_6" => "custom_field_six",
    "custom_field_7" => "custom_field_seven"
  }

  @spec enabled?(map()) :: boolean()
  def enabled?(tracker),
    do: is_binary(workflow_field(tracker)) or is_binary(workflow_field(tracker, "story"))

  @spec validate(map()) :: :ok | {:error, term()}
  def validate(settings) when is_map(settings) do
    tracker = map_value(settings, "tracker") || %{}
    platform = nested(tracker, [:provider, "platform"]) || %{}

    with :ok <-
           validate_field_config(
             map_value(platform, "bug_ai_workflow"),
             :invalid_tapd_bug_ai_workflow
           ),
         :ok <-
           validate_field_config(
             map_value(platform, "bug_ai_model_level"),
             :invalid_tapd_bug_ai_model_level
           ),
         :ok <-
           validate_field_config(
             map_value(platform, "task_ai_workflow") || map_value(platform, "story_ai_workflow"),
             :invalid_tapd_task_ai_workflow
           ),
         :ok <-
           validate_field_config(
             map_value(platform, "task_ai_model_level") || map_value(platform, "story_ai_model_level"),
             :invalid_tapd_task_ai_model_level
           ) do
      :ok
    else
      {:error, reason} -> {:error, tracker_config_error(reason)}
    end
  end

  def validate(_settings), do: :ok

  @spec workflow_field(map()) :: String.t() | nil
  def workflow_field(tracker), do: configured_field(tracker, "bug_ai_workflow")

  @spec workflow_field(map(), String.t()) :: String.t() | nil
  def workflow_field(tracker, "story") do
    configured_field(tracker, "task_ai_workflow") ||
      configured_field(tracker, "story_ai_workflow")
  end

  def workflow_field(tracker, _entity_type), do: workflow_field(tracker)

  @spec model_level_field(map()) :: String.t() | nil
  def model_level_field(tracker), do: configured_field(tracker, "bug_ai_model_level")

  @spec model_level_field(map(), String.t()) :: String.t() | nil
  def model_level_field(tracker, "story") do
    configured_field(tracker, "task_ai_model_level") ||
      configured_field(tracker, "story_ai_model_level")
  end

  def model_level_field(tracker, _entity_type), do: model_level_field(tracker)

  @spec valid_field?(term()) :: boolean()
  def valid_field?(value) when is_binary(value),
    do: Regex.match?(~r/^custom_field_[a-z0-9_]+$/, value)

  def valid_field?(_value), do: false

  @spec active_states(map()) :: [String.t()]
  def active_states(tracker) do
    case nested(tracker, [:provider, "platform", "bug_ai_workflow", "active_states"]) do
      values when is_list(values) -> normalize_list(values, @default_active_states)
      _value -> @default_active_states
    end
  end

  @spec active_states(map(), String.t()) :: [String.t()]
  def active_states(tracker, "story") do
    case nested(tracker, [:provider, "platform", "task_ai_workflow", "active_states"]) ||
           nested(tracker, [:provider, "platform", "story_ai_workflow", "active_states"]) do
      values when is_list(values) -> normalize_list(values, @default_task_active_states)
      _value -> @default_task_active_states
    end
  end

  def active_states(tracker, _entity_type), do: active_states(tracker)

  @spec accepted_value(map()) :: String.t()
  def accepted_value(tracker),
    do: workflow_value(tracker, "accepted_value", @default_accepted_value)

  @spec resolved_value(map()) :: String.t()
  def resolved_value(tracker),
    do: workflow_value(tracker, "resolved_value", @default_resolved_value)

  @spec exception_value(map()) :: String.t()
  def exception_value(tracker),
    do: workflow_value(tracker, "exception_value", @default_exception_value)

  @spec model_level(map(), map()) :: String.t()
  def model_level(raw_issue, tracker) do
    raw_issue
    |> field_value(model_level_field(tracker))
    |> normalize_string()
    |> then(fn value -> if is_binary(value), do: String.downcase(value) end)
    |> case do
      level when level in @supported_model_levels -> level
      _level -> @default_model_level
    end
  end

  @spec model_level(map(), map(), String.t()) :: String.t()
  def model_level(raw_issue, tracker, entity_type),
    do: normalize_model_level(raw_issue, model_level_field(tracker, entity_type))

  @spec field_value(map(), String.t() | nil) :: String.t() | nil
  def field_value(raw_issue, field) when is_map(raw_issue) and is_binary(field),
    do:
      raw_issue
      |> field_value_from_api_names(field)
      |> normalize_string()

  def field_value(_raw_issue, _field), do: nil

  defp field_value_from_api_names(raw_issue, field) do
    map_value(raw_issue, field) ||
      case Map.get(@story_field_aliases, field) do
        alias_field when is_binary(alias_field) -> map_value(raw_issue, alias_field)
        _ -> nil
      end
  end

  defp normalize_model_level(raw_issue, field) do
    raw_issue
    |> field_value(field)
    |> normalize_string()
    |> then(fn value -> if is_binary(value), do: String.downcase(value) end)
    |> case do
      level when level in @supported_model_levels -> level
      _level -> @default_model_level
    end
  end

  defp configured_field(tracker, config_key) do
    tracker
    |> nested([:provider, "platform", config_key, "field"])
    |> normalize_string()
    |> case do
      value when is_binary(value) -> if valid_field?(value), do: value
      _value -> nil
    end
  end

  defp validate_field_config(nil, _reason), do: :ok

  defp validate_field_config(config, reason) when is_map(config) do
    case map_value(config, "field") do
      nil -> :ok
      field -> if valid_field?(field), do: :ok, else: {:error, reason}
    end
  end

  defp validate_field_config(_config, reason), do: {:error, reason}

  defp tracker_config_error(reason) do
    SymphonyElixir.Tracker.Error.new(%{
      provider: "tapd",
      operation: :validate_config,
      code: :invalid_configuration,
      message: "TAPD company policy configuration is invalid or incomplete.",
      details: %{source_reason: reason}
    })
  end

  defp workflow_value(tracker, key, default) do
    tracker
    |> nested([:provider, "platform", "bug_ai_workflow", key])
    |> Kernel.||(nested(tracker, [:provider, "platform", "task_ai_workflow", key]))
    |> Kernel.||(nested(tracker, [:provider, "platform", "story_ai_workflow", key]))
    |> normalize_string()
    |> Kernel.||(default)
  end

  defp normalize_list(values, default) do
    case values |> Enum.map(&normalize_string/1) |> Enum.reject(&is_nil/1) |> Enum.uniq() do
      [] -> default
      normalized -> normalized
    end
  end

  defp nested(value, []), do: value

  defp nested(map, [key | rest]) when is_map(map),
    do: map |> map_value(to_string(key)) |> nested(rest)

  defp nested(_value, _path), do: nil

  defp map_value(map, key) when is_map(map) do
    Map.get(map, key) || existing_atom_value(map, key)
  end

  defp existing_atom_value(map, key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_string(_value), do: nil
end
