defmodule BackendWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :backend

  # Phoenix Channels transport. Each connected client becomes one BEAM
  # process; heartbeats, close handling, and topic fan-out are framework
  # code — this line plus the two channel modules is the entire WebSocket
  # layer (the Go project's hub.go + ws.go).
  socket "/ws", BackendWeb.UserSocket,
    websocket: [timeout: 45_000],
    longpoll: false

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason

  plug BackendWeb.Router
end
