defmodule BackendWeb.NoteController do
  use Phoenix.Controller, formats: [:json]

  alias Backend.Notes

  def index(conn, _params), do: json(conn, Notes.list())

  def show(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         %{} = note <- Notes.get(id) do
      json(conn, note)
    else
      nil -> error(conn, 404, "not found")
      :error -> error(conn, 400, "invalid id")
    end
  end

  def create(conn, params) do
    case Notes.create(params) do
      {:ok, note} -> conn |> put_status(201) |> json(note)
      {:error, :invalid} -> error(conn, 400, "title must be 1..200 characters")
      {:error, _} -> error(conn, 500, "internal error")
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, id} <- parse_id(id) do
      case Notes.update(id, params) do
        {:ok, note} -> json(conn, note)
        {:error, :invalid} -> error(conn, 400, "title must be 1..200 characters")
        {:error, :not_found} -> error(conn, 404, "not found")
        {:error, _} -> error(conn, 500, "internal error")
      end
    else
      :error -> error(conn, 400, "invalid id")
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id) do
      case Notes.delete(id) do
        :ok -> send_resp(conn, 204, "")
        {:error, :not_found} -> error(conn, 404, "not found")
        {:error, _} -> error(conn, 500, "internal error")
      end
    else
      :error -> error(conn, 400, "invalid id")
    end
  end

  def events(conn, params) do
    since =
      case Integer.parse(Map.get(params, "since", "0")) do
        {n, _} when n >= 0 -> n
        _ -> 0
      end

    json(conn, Notes.events_since(since))
  end

  defp parse_id(raw) do
    case Integer.parse(raw) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> :error
    end
  end

  defp error(conn, status, msg) do
    conn |> put_status(status) |> json(%{error: msg})
  end
end
