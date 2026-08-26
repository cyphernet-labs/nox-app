defmodule BackendWeb.UserSocket do
  use Phoenix.Socket

  channel "events:*", BackendWeb.EventsChannel

  # Runs once per WebSocket connection, before any channel join.
  # TODO: authenticate here — e.g. verify a signed token from
  # params["token"] (Phoenix.Token.verify/4) and return :error to reject.
  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
