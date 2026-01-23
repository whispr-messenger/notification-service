defmodule WhisprNotificationsWeb.MuteController do
  use WhisprNotificationsWeb, :controller

  # POST /api/conversations/:conversation_id/mute?user_id=...
  def mute(conn, %{"conversation_id" => conversation_id, "user_id" => user_id}) do
    # TODO: persister les ConversationSettings.muted = true
    _ = {conversation_id, user_id}
    send_resp(conn, 204, "")
  end

  # DELETE /api/conversations/:conversation_id/mute?user_id=...
  def unmute(conn, %{"conversation_id" => conversation_id, "user_id" => user_id}) do
    # TODO: persister les ConversationSettings.muted = false
    _ = {conversation_id, user_id}
    send_resp(conn, 204, "")
  end
end
