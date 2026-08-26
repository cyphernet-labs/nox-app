defmodule Backend.Notes do
  @moduledoc """
  All note operations. Same write pattern as the Go project:

    1. one BEGIN IMMEDIATE transaction (via DB.Writer): mutate the row AND
       insert the outbox `events` row — so a notification can never exist
       for uncommitted data;
    2. after COMMIT: broadcast the event on topic "events:all"; every
       joined channel process pushes it to its client.
  """
  alias Backend.DB
  alias Backend.DB.Writer

  @topic "events:all"

  # ---- reads (concurrent, snapshot-isolated by WAL) ----

  def list do
    DB.with_read(&DB.query(&1, "SELECT id, title, body, updated_at FROM notes ORDER BY id"))
  end

  def get(id) do
    DB.with_read(fn conn ->
      case DB.query(conn, "SELECT id, title, body, updated_at FROM notes WHERE id = ?1", [id]) do
        [note] -> note
        [] -> nil
      end
    end)
  end

  def events_since(seq) do
    DB.with_read(fn conn ->
      conn
      |> DB.query(
        """
        SELECT seq, type, entity, entity_id, payload, created_at
          FROM events WHERE seq > ?1 ORDER BY seq
        """,
        [seq]
      )
      |> Enum.map(&decode_event/1)
    end)
  end

  # ---- writes (serialized through the Writer process) ----

  def create(%{"title" => title} = attrs) when is_binary(title) do
    with :ok <- validate(title) do
      body = Map.get(attrs, "body", "")

      Writer.transaction(fn conn ->
        [note] =
          DB.query(
            conn,
            """
            INSERT INTO notes (title, body) VALUES (?1, ?2)
            RETURNING id, title, body, updated_at
            """,
            [String.trim(title), body]
          )

        {note, insert_event(conn, "note.created", note["id"], note)}
      end)
      |> broadcast()
    end
  end

  def create(_), do: {:error, :invalid}

  def update(id, %{"title" => title} = attrs) when is_binary(title) do
    with :ok <- validate(title) do
      body = Map.get(attrs, "body", "")

      Writer.transaction(fn conn ->
        case DB.query(
               conn,
               """
               UPDATE notes SET title = ?1, body = ?2, updated_at = unixepoch()
                WHERE id = ?3
               RETURNING id, title, body, updated_at
               """,
               [String.trim(title), body, id]
             ) do
          [note] -> {note, insert_event(conn, "note.updated", note["id"], note)}
          [] -> :not_found
        end
      end)
      |> case do
        {:ok, :not_found} -> {:error, :not_found}
        other -> broadcast(other)
      end
    end
  end

  def update(_, _), do: {:error, :invalid}

  def delete(id) do
    Writer.transaction(fn conn ->
      case DB.query(conn, "DELETE FROM notes WHERE id = ?1 RETURNING id", [id]) do
        [%{"id" => ^id}] ->
          {:deleted, insert_event(conn, "note.deleted", id, %{"id" => id})}

        [] ->
          :not_found
      end
    end)
    |> case do
      {:ok, :not_found} -> {:error, :not_found}
      {:ok, {:deleted, event}} -> push_event(event) && :ok
      {:error, _} = e -> e
    end
  end

  # ---- internals ----

  defp validate(title) do
    t = String.trim(title)
    if t != "" and String.length(t) <= 200, do: :ok, else: {:error, :invalid}
  end

  # Runs INSIDE the write transaction.
  defp insert_event(conn, type, entity_id, payload) do
    [event] =
      DB.query(
        conn,
        """
        INSERT INTO events (type, entity, entity_id, payload)
        VALUES (?1, 'note', ?2, ?3)
        RETURNING seq, type, entity, entity_id, payload, created_at
        """,
        [type, entity_id, Jason.encode!(payload)]
      )

    decode_event(event)
  end

  # payload is stored as JSON text; decode before handing to clients.
  defp decode_event(event), do: Map.update!(event, "payload", &Jason.decode!/1)

  defp broadcast({:ok, {note, event}}) do
    push_event(event)
    {:ok, note}
  end

  defp broadcast({:error, _} = e), do: e

  defp push_event(event) do
    # Endpoint.broadcast delivers to every channel process joined on the
    # topic, which pushes the frame to its client. (Coupling of context to
    # web layer accepted for boilerplate; the seam to cut later is a
    # Phoenix.PubSub.broadcast plus handle_out in the channel.)
    :ok = BackendWeb.Endpoint.broadcast(@topic, "event", event)
    true
  end
end
