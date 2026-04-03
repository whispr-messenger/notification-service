defmodule WhisprNotifications.Notifications do
  @moduledoc """
  Création et envoi des notifications utilisateur.
  """

  alias WhisprNotifications.Devices.CacheManager
  alias WhisprNotifications.Delivery.BatchProcessor
  alias WhisprNotifications.Notifications.{History, Notification}

  @spec create(map()) :: {:ok, Notification.t()} | {:error, :validation, [String.t()]}
  def create(params) when is_map(params) do
    attrs = normalize_params(params)

    case validate(attrs) do
      [] ->
        notif = Notification.new(attrs)
        :ok = History.save(notif)
        _ = deliver_if_possible(notif)
        {:ok, notif}

      errors ->
        {:error, :validation, errors}
    end
  end

  defp normalize_params(params) do
    ctx = params["context"] || params[:context] || %{}
    ctx = if is_map(ctx), do: stringify_context(ctx), else: %{}

    %{
      user_id: params["user_id"] || params[:user_id],
      type: parse_type(params["type"] || params[:type]),
      title: params["title"] || params[:title],
      body: params["body"] || params[:body],
      context: ctx,
      conversation_id: params["conversation_id"] || params[:conversation_id],
      metadata: params["metadata"] || params[:metadata] || %{}
    }
  end

  defp stringify_context(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {to_string(k), v}
    end)
  end

  defp parse_type(nil), do: nil

  defp parse_type(t) when is_atom(t), do: t

  defp parse_type(t) when is_binary(t) do
    case t do
      "message" -> :message
      "group" -> :group
      "system" -> :system
      _ -> :invalid
    end
  end

  defp validate_present(v, msg) do
    case v do
      nil -> [msg]
      "" -> [msg]
      s when is_binary(s) -> []
      _ -> [msg]
    end
  end

  defp validate_type(:invalid), do: ["type doit être message, group ou system"]
  defp validate_type(nil), do: ["type est requis"]
  defp validate_type(t) when t in [:message, :group, :system], do: []
  defp validate_type(_), do: ["type doit être message, group ou system"]

  defp validate_context(ctx) when is_map(ctx), do: []
  defp validate_context(_), do: ["context doit être un objet JSON"]

  defp validate_present_list(acc, v, msg) do
    case validate_present(v, msg) do
      [] -> acc
      errs -> acc ++ errs
    end
  end

  defp validate(attrs) do
    errs =
      []
      |> validate_present_list(attrs.user_id, "user_id est requis")
      |> validate_present_list(attrs.title, "title est requis")
      |> validate_present_list(attrs.body, "body est requis")
      |> then(fn acc -> acc ++ validate_type(attrs.type) end)
      |> then(fn acc -> acc ++ validate_context(attrs.context) end)

    errs
  end

  defp deliver_if_possible(%Notification{user_id: user_id} = notif) do
    case CacheManager.get_cache(user_id) do
      {:ok, cache} -> BatchProcessor.deliver(notif, cache)
      _ -> :ok
    end
  end
end
