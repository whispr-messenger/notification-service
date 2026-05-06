defmodule WhisprNotifications.JsonFormatterExtraTest do
  use ExUnit.Case, async: true

  alias WhisprNotifications.JsonFormatter

  @ts {{2026, 4, 22}, {12, 34, 56, 789}}

  test "passes booleans and nil through unchanged" do
    output =
      JsonFormatter.format(:info, "x", @ts,
        active: true,
        disabled: false,
        absent: nil
      )

    payload = Jason.decode!(String.trim(IO.iodata_to_binary(output)))

    assert payload["active"] == true
    assert payload["disabled"] == false
    assert payload["absent"] == nil
  end

  test "serialises tuples as JSON arrays" do
    output =
      JsonFormatter.format(:info, "x", @ts, coords: {1, 2, "three"})

    payload = Jason.decode!(String.trim(IO.iodata_to_binary(output)))

    assert payload["coords"] == [1, 2, "three"]
  end

  test "stringifies non-atom non-binary metadata keys via inspect" do
    output =
      JsonFormatter.format(:info, "x", @ts, nested: %{42 => "answer", {:a, :b} => "tuple-key"})

    payload = Jason.decode!(String.trim(IO.iodata_to_binary(output)))

    keys = payload["nested"] |> Map.keys()

    # Either int-key or tuple-key inspect form must be present;
    # both go through sanitize_key/1's catch-all clause.
    assert Enum.any?(keys, &(&1 == "42")) or Enum.any?(keys, &String.starts_with?(&1, "{"))
  end

  test "safe_chardata_to_string falls back to inspect for invalid chardata" do
    # Atoms aren't valid chardata; IO.chardata_to_string raises and the
    # safe wrapper inspects.
    output = JsonFormatter.format(:info, :not_chardata, @ts, [])

    payload = Jason.decode!(String.trim(IO.iodata_to_binary(output)))

    assert payload["message"] == ":not_chardata"
  end

  test "stringifies atom keys inside nested maps via sanitize_key/1" do
    output =
      JsonFormatter.format(:info, "x", @ts, nested: %{atom_key: "value", another: 1})

    payload = Jason.decode!(String.trim(IO.iodata_to_binary(output)))

    assert payload["nested"]["atom_key"] == "value"
    assert payload["nested"]["another"] == 1
  end

  test "falls back to a textual frame when JSON encoding raises" do
    # An invalid UTF-8 binary in metadata defeats Jason.encode_to_iodata!; the
    # rescue branch must emit a minimal `{"level":..,"message":..}` frame
    # (with newlines escaped) instead of crashing the logger.
    invalid_utf8 = <<0xFF, 0xFE, 0xFD>>

    output = JsonFormatter.format(:error, "boom\nline2", @ts, bad: invalid_utf8)

    raw = IO.iodata_to_binary(output)

    assert String.ends_with?(raw, "\n")
    assert String.contains?(raw, ~s|"level":"error"|)
    assert String.contains?(raw, "formatter error:")
    # Newlines in the error message must be escaped, not bare.
    body = String.trim_trailing(raw, "\n")
    refute String.contains?(body, "\n")
  end
end
