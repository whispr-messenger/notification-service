defmodule WhisprNotifications.NotificationsTest do
  use WhisprNotifications.DataCase, async: false

  alias WhisprNotifications.Notifications
  alias WhisprNotifications.Notifications.Notification

  describe "create/1 success" do
    test "returns an ok tuple with a valid notification (string keys)" do
      assert {:ok, %Notification{} = notif} =
               Notifications.create(%{
                 "user_id" => "u-ok-1",
                 "type" => "message",
                 "title" => "Hello",
                 "body" => "World",
                 "context" => %{"conversation_id" => "c-1"},
                 "conversation_id" => "c-1"
               })

      assert notif.type == :message
      assert notif.title == "Hello"
      assert notif.body == "World"
      assert notif.user_id == "u-ok-1"
      assert notif.conversation_id == "c-1"
      assert is_binary(notif.id)
      assert %DateTime{} = notif.created_at
    end

    test "accepts atom keys and atom type" do
      assert {:ok, %Notification{type: :group}} =
               Notifications.create(%{
                 user_id: "u-ok-2",
                 type: :group,
                 title: "t",
                 body: "b",
                 context: %{foo: "bar"}
               })
    end

    test "defaults context to an empty map when missing" do
      assert {:ok, %Notification{context: ctx}} =
               Notifications.create(%{
                 user_id: "u-ok-3",
                 type: "system",
                 title: "t",
                 body: "b"
               })

      assert ctx == %{}
    end

    test "stringifies atom-keyed context" do
      assert {:ok, %Notification{context: %{"foo" => "bar"}}} =
               Notifications.create(%{
                 user_id: "u-ok-4",
                 type: "system",
                 title: "t",
                 body: "b",
                 context: %{foo: "bar"}
               })
    end

    test "parses each valid type string" do
      for {str, atom} <- [{"message", :message}, {"group", :group}, {"system", :system}] do
        assert {:ok, %Notification{type: ^atom}} =
                 Notifications.create(%{
                   user_id: "u-ok-types",
                   type: str,
                   title: "t",
                   body: "b"
                 })
      end
    end
  end

  describe "create/1 validation errors" do
    test "rejects missing user_id" do
      assert {:error, :validation, errs} =
               Notifications.create(%{
                 "type" => "message",
                 "title" => "t",
                 "body" => "b"
               })

      assert "user_id est requis" in errs
    end

    test "rejects missing title and body" do
      assert {:error, :validation, errs} =
               Notifications.create(%{
                 "user_id" => "u",
                 "type" => "message"
               })

      assert "title est requis" in errs
      assert "body est requis" in errs
    end

    test "rejects invalid type" do
      assert {:error, :validation, errs} =
               Notifications.create(%{
                 "user_id" => "u",
                 "type" => "nonsense",
                 "title" => "t",
                 "body" => "b"
               })

      assert "type doit être message, group ou system" in errs
    end

    test "rejects missing type" do
      assert {:error, :validation, errs} =
               Notifications.create(%{
                 "user_id" => "u",
                 "title" => "t",
                 "body" => "b"
               })

      assert "type est requis" in errs
    end

    test "silently defaults non-map context to an empty map" do
      assert {:ok, notif} =
               Notifications.create(%{
                 "user_id" => "u",
                 "type" => "message",
                 "title" => "t",
                 "body" => "b",
                 "context" => "not-a-map"
               })

      assert notif.context == %{}
    end
  end
end
