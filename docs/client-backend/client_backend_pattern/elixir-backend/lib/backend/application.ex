defmodule Backend.Application do
  @moduledoc """
  Supervision tree. Order matters:

    1. PubSub — the fan-out transport;
    2. DB.Writer — the single BEAM process owning the sole write
       connection; it also runs migrations in init/1, so the schema is
       ready before the endpoint accepts a single request;
    3. Endpoint — HTTP + WebSocket listener.

  Any child crashing is restarted by this supervisor (one_for_one).
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Backend.PubSub},
      Backend.DB.Writer,
      BackendWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Backend.Supervisor)
  end
end
