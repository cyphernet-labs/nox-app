defmodule BackendWeb.EventsChannel do
  @moduledoc """
  Topic "events:all". Client joins with %{"last_seq" => N} (0 initially);
  events with seq > N are replayed as individual "event" pushes, then live
  events arrive on the same "event" push as they are broadcast.

  Ordering guarantee, same as the Go project: this channel process is
  subscribed to the topic by the time join/3 returns, and the replay runs
  from its own mailbox message afterwards — so nothing committed in the
  gap is lost. Duplicates at the replay/live boundary are possible;
  clients MUST de-duplicate by seq (ignore any seq <= last seen).
  """
  use Phoenix.Channel

  @impl true
  def join("events:all", params, socket) do
    last_seq =
      case params do
        %{"last_seq" => n} when is_integer(n) and n >= 0 -> n
        _ -> 0
      end

    send(self(), {:replay, last_seq})
    {:ok, socket}
  end

  @impl true
  def handle_info({:replay, last_seq}, socket) do
    for event <- Backend.Notes.events_since(last_seq) do
      push(socket, "event", event)
    end

    {:noreply, socket}
  end
end
