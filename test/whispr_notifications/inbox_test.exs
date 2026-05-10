defmodule WhisprNotifications.InboxTest do
  use WhisprNotifications.DataCase, async: true

  alias WhisprNotifications.Inbox
  alias WhisprNotifications.Inbox.Item

  @user_a "user-inbox-test-a"
  @user_b "user-inbox-test-b"

  describe "insert/3" do
    test "insere un item et retourne {:ok, Item.t()}" do
      assert {:ok, %Item{} = item} =
               Inbox.insert(@user_a, "mention", %{"conversation_id" => "conv-1"})

      assert item.user_id == @user_a
      assert item.event_type == "mention"
      assert item.payload == %{"conversation_id" => "conv-1"}
      assert is_nil(item.read_at)
      assert is_binary(item.id)
    end

    test "retourne {:error, changeset} pour un event_type invalide" do
      assert {:error, changeset} = Inbox.insert(@user_a, "unknown_event", %{})
      assert Keyword.has_key?(changeset.errors, :event_type)
    end

    test "accepte tous les event_type valides" do
      for event_type <- ~w(mention reply contact_request missed_call) do
        assert {:ok, _item} = Inbox.insert(@user_a, event_type, %{"x" => event_type})
      end
    end
  end

  describe "list/2" do
    test "retourne uniquement les items de l'utilisateur concerne" do
      {:ok, _} = Inbox.insert(@user_a, "mention", %{})
      {:ok, _} = Inbox.insert(@user_b, "reply", %{})

      items = Inbox.list(@user_a)
      assert length(items) == 1
      assert hd(items).user_id == @user_a
    end

    test "respecte la limite par defaut (20) et le max (50)" do
      for i <- 1..25 do
        {:ok, _} = Inbox.insert(@user_a, "mention", %{"i" => i})
      end

      items_default = Inbox.list(@user_a)
      assert length(items_default) == 20

      items_limit = Inbox.list(@user_a, limit: 50)
      assert length(items_limit) == 25
    end

    test "pagination par curseur - retourne les items apres le curseur" do
      for i <- 1..5 do
        {:ok, _} = Inbox.insert(@user_a, "mention", %{"i" => i})
        # petit delai pour que les timestamps different
        Process.sleep(2)
      end

      all_items = Inbox.list(@user_a, limit: 10)
      assert length(all_items) == 5

      # le curseur est le 3eme item (index 2 dans la liste desc)
      cursor_item = Enum.at(all_items, 2)
      after_cursor = Inbox.list(@user_a, cursor: cursor_item.id, limit: 10)

      # on doit avoir les 2 items les plus anciens
      assert length(after_cursor) == 2
      refute Enum.any?(after_cursor, fn i -> i.id == cursor_item.id end)
    end
  end

  describe "count_unread/1" do
    test "retourne 0 quand pas d'items" do
      assert Inbox.count_unread(@user_a) == 0
    end

    test "compte uniquement les items non lus de l'utilisateur" do
      {:ok, item1} = Inbox.insert(@user_a, "mention", %{})
      {:ok, _item2} = Inbox.insert(@user_a, "reply", %{})
      # item d'un autre user - ne doit pas compter
      {:ok, _} = Inbox.insert(@user_b, "mention", %{})

      assert Inbox.count_unread(@user_a) == 2

      # marquer un comme lu
      {:ok, 1} = Inbox.mark_read(@user_a, [item1.id])
      assert Inbox.count_unread(@user_a) == 1
    end
  end

  describe "mark_read/2" do
    test "mark_read avec :all marque tous les items non lus" do
      {:ok, _} = Inbox.insert(@user_a, "mention", %{})
      {:ok, _} = Inbox.insert(@user_a, "reply", %{})

      {:ok, count} = Inbox.mark_read(@user_a, :all)
      assert count == 2
      assert Inbox.count_unread(@user_a) == 0
    end

    test "mark_read avec liste d'ids marque uniquement les items specifies" do
      {:ok, item1} = Inbox.insert(@user_a, "mention", %{})
      {:ok, _item2} = Inbox.insert(@user_a, "reply", %{})

      {:ok, count} = Inbox.mark_read(@user_a, [item1.id])
      assert count == 1
      assert Inbox.count_unread(@user_a) == 1
    end

    test "anti-IDOR : mark_read ne peut pas lire les items d'un autre utilisateur" do
      {:ok, item_b} = Inbox.insert(@user_b, "mention", %{})

      # user_a essaie de marquer l'item de user_b comme lu
      {:ok, count} = Inbox.mark_read(@user_a, [item_b.id])
      assert count == 0

      # l'item de user_b reste non lu
      assert Inbox.count_unread(@user_b) == 1
    end

    test "mark_read avec liste vide retourne {:ok, 0}" do
      {:ok, result} = Inbox.mark_read(@user_a, [])
      assert result == 0
    end

    test "mark_read :all idempotent (deuxieme appel retourne 0)" do
      {:ok, _} = Inbox.insert(@user_a, "mention", %{})
      {:ok, _} = Inbox.mark_read(@user_a, :all)
      {:ok, second} = Inbox.mark_read(@user_a, :all)
      assert second == 0
    end
  end
end
