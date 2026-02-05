defmodule WhisprNotifications.Delivery.RetryManager do
  @moduledoc """
  Gestion des retries pour les envois qui échouent.
  On garde la logique séparée du client de transport.
  """

  @type attempt :: %{
          device: map(),
          payload: map(),
          platform: :ios | :android,
          retries: non_neg_integer()
        }

  @max_retries 3

  @spec should_retry?(attempt()) :: boolean()
  def should_retry?(%{retries: r}) when r < @max_retries, do: true
  def should_retry?(_), do: false

  @spec next_attempt(attempt()) :: attempt()
  def next_attempt(%{retries: r} = attempt) do
    %{attempt | retries: r + 1}
  end
end
