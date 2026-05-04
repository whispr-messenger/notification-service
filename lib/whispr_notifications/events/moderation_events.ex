defmodule WhisprNotifications.Events.ModerationEvents do
  @moduledoc """
  Handles moderation-related events and converts them to push notifications.

  Subscribes to Redis channels:
  - whispr:moderation:report_created
  - whispr:moderation:sanction_applied
  - whispr:moderation:sanction_lifted
  - whispr:moderation:appeal_created
  - whispr:moderation:appeal_resolved
  - whispr:moderation:threshold_reached
  - whispr:moderation:blocked_image_approved
  - whispr:moderation:blocked_image_rejected
  """

  require Logger

  alias WhisprNotifications.Notifications
  alias WhisprNotifications.Notifications.Notification
  alias WhisprNotificationsWeb.Endpoint

  @doc "Notify admins when a new report is created."
  @spec handle_report_created(map()) :: {:ok, Notification.t()} | {:error, term()}
  def handle_report_created(payload) do
    Notifications.create(%{
      user_id: "admin",
      type: :system,
      title: "New moderation report",
      body: "A #{payload["category"]} report has been submitted",
      context: %{
        "event" => "report_created",
        "report_id" => payload["report_id"],
        "reporter_id" => payload["reporter_id"],
        "reported_user_id" => payload["reported_user_id"],
        "category" => payload["category"]
      }
    })
    |> log_result("Report created notification", report_id: payload["report_id"])
  end

  @doc "Notify a user when a sanction is applied to them."
  @spec handle_sanction_applied(map()) :: {:ok, Notification.t()} | {:error, term()}
  def handle_sanction_applied(payload) do
    title =
      case payload["sanction_type"] do
        "mute" -> "You have been muted"
        "kick" -> "You have been removed from a conversation"
        "warning" -> "You have received a warning"
        "temp_ban" -> "Your account has been temporarily suspended"
        "perm_ban" -> "Your account has been suspended"
        _ -> "Moderation action taken"
      end

    body = "Reason: #{payload["reason"] || "Violation of community guidelines"}"

    body =
      if payload["expires_at"],
        do: body <> ". Expires: #{payload["expires_at"]}",
        else: body

    Notifications.create(%{
      user_id: payload["user_id"],
      type: :system,
      title: title,
      body: body,
      context: %{
        "event" => "sanction_applied",
        "sanction_type" => payload["sanction_type"],
        "reason" => payload["reason"],
        "expires_at" => payload["expires_at"]
      }
    })
    |> log_result("Sanction notification", user_id: payload["user_id"])
  end

  @doc "Notify a user when a sanction is lifted."
  @spec handle_sanction_lifted(map()) :: {:ok, Notification.t()} | {:error, term()}
  def handle_sanction_lifted(payload) do
    Notifications.create(%{
      user_id: payload["user_id"],
      type: :system,
      title: "Sanction lifted",
      body: "A moderation sanction on your account has been lifted.",
      context: %{
        "event" => "sanction_lifted",
        "sanction_id" => payload["sanction_id"]
      }
    })
    |> log_result("Sanction lifted notification", user_id: payload["user_id"])
  end

  @doc "Notify admins when an appeal is created."
  @spec handle_appeal_created(map()) :: {:ok, Notification.t()} | {:error, term()}
  def handle_appeal_created(payload) do
    Notifications.create(%{
      user_id: "admin",
      type: :system,
      title: "New appeal submitted",
      body: "A user has contested a moderation sanction",
      context: %{
        "event" => "appeal_created",
        "appeal_id" => payload["appeal_id"],
        "user_id" => payload["user_id"],
        "sanction_id" => payload["sanction_id"]
      }
    })
    |> log_result("Appeal created notification", appeal_id: payload["appeal_id"])
  end

  @doc "Notify the appellant when their appeal is resolved."
  @spec handle_appeal_resolved(map()) :: {:ok, Notification.t()} | {:error, term()}
  def handle_appeal_resolved(payload) do
    {title, body} =
      case payload["status"] do
        "accepted" ->
          {"Appeal accepted", "Your appeal has been accepted and the sanction has been lifted."}

        "rejected" ->
          {"Appeal rejected",
           "Your appeal has been reviewed and rejected. #{payload["reviewer_notes"] || ""}"}

        _ ->
          {"Appeal update", "Your appeal has been reviewed."}
      end

    Notifications.create(%{
      user_id: payload["user_id"],
      type: :system,
      title: title,
      body: String.trim(body),
      context: %{
        "event" => "appeal_resolved",
        "appeal_id" => payload["appeal_id"],
        "status" => payload["status"]
      }
    })
    |> log_result("Appeal resolved notification",
      user_id: payload["user_id"],
      appeal_id: payload["appeal_id"]
    )
  end

  @doc "Warn admins when a user is approaching the auto-sanction threshold."
  @spec handle_threshold_warning(map()) :: {:ok, Notification.t()} | {:error, term()}
  def handle_threshold_warning(payload) do
    Notifications.create(%{
      user_id: "admin",
      type: :system,
      title: "User approaching auto-sanction",
      body:
        "User has #{payload["report_count"]} reports — threshold: #{payload["threshold_level"]}",
      context: %{
        "event" => "threshold_warning",
        "reported_user_id" => payload["reported_user_id"],
        "threshold_level" => payload["threshold_level"],
        "report_count" => payload["report_count"]
      }
    })
    |> log_result("Threshold warning", reported_user_id: payload["reported_user_id"])
  end

  @doc "Notify a user when their blocked image appeal has been reviewed."
  @spec handle_blocked_image_decision(map(), String.t()) ::
          {:ok, Notification.t()} | {:error, term()}
  def handle_blocked_image_decision(payload, decision)
      when decision in ["approved", "rejected"] do
    {title, body} =
      case decision do
        "approved" ->
          {"Image appeal approved",
           "Your contested image has been approved and will be delivered."}

        "rejected" ->
          {"Image appeal rejected",
           String.trim(
             "Your contested image has been rejected. #{payload["reviewerNotes"] || ""}"
           )}
      end

    context =
      %{
        "event" => "blocked_image_decision",
        "appealId" => payload["appealId"],
        "decision" => decision,
        "messageTempId" => payload["messageTempId"],
        "conversationId" => payload["conversationId"],
        "reason" => payload["reviewerNotes"]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    case payload["userId"] do
      user_id when user_id in [nil, ""] ->
        Logger.warning(
          "[ModerationEvents] Blocked image appeal #{decision} notification not created: missing userId",
          appeal_id: payload["appealId"]
        )

        {:error, :missing_user_id}

      user_id ->
        broadcast_blocked_image_decision(user_id, decision, payload)

        Notifications.create(%{
          user_id: user_id,
          type: :system,
          title: title,
          body: body,
          context: context
        })
        |> log_result("Blocked image appeal #{decision} notification",
          user_id: user_id,
          appeal_id: payload["appealId"]
        )
    end
  end

  defp broadcast_blocked_image_decision(user_id, "approved", payload) do
    data = %{
      "appealId" => payload["appealId"],
      "decision" => "approved",
      "messageTempId" => payload["messageTempId"],
      "conversationId" => payload["conversationId"],
      "reviewerNotes" => payload["reviewerNotes"]
    }

    Endpoint.broadcast("user:#{user_id}", "blocked_image_decision", data)
  end

  defp broadcast_blocked_image_decision(user_id, "rejected", payload) do
    data = %{
      "appealId" => payload["appealId"],
      "decision" => "rejected",
      "messageTempId" => payload["messageTempId"],
      "reviewerNotes" => payload["reviewerNotes"]
    }

    Endpoint.broadcast("user:#{user_id}", "blocked_image_decision", data)
  end

  defp log_result({:ok, _} = result, label, metadata) do
    Logger.info("[ModerationEvents] #{label} sent", metadata)
    result
  end

  defp log_result({:error, kind, details} = result, label, metadata) do
    Logger.error(
      "[ModerationEvents] #{label} failed: #{inspect({kind, details})}",
      metadata
    )

    result
  end
end
