defmodule BackendWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", BackendWeb do
    pipe_through :api

    get "/notes", NoteController, :index
    get "/notes/:id", NoteController, :show
    post "/notes", NoteController, :create
    put "/notes/:id", NoteController, :update
    delete "/notes/:id", NoteController, :delete

    # REST fallback for the outbox (poll / catch-up without a socket).
    get "/events", NoteController, :events
  end
end
