defmodule Backend.DB.Writer do
  @moduledoc """
  The single writer. One BEAM process owns the ONE write connection for the
  whole node; all mutations are GenServer.call-s into it, so writes are
  serialized by the process mailbox — the same structural guarantee the Go
  project gets from MaxOpenConns(1), expressed as a process instead of a
  pool limit. In-process SQLITE_BUSY between writers is unreachable.

  Migrations run in init/1: the supervisor starts this process before the
  endpoint, so no request is served against a stale schema.
  """
  use GenServer

  alias Backend.DB
  alias Exqlite.Sqlite3

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc """
  Run `fun.(conn)` inside BEGIN IMMEDIATE ... COMMIT on the write
  connection. Returns {:ok, fun_result} or {:error, reason} (rolled back).
  Keep transactions to milliseconds: no network calls, no sleeping inside.
  """
  def transaction(fun), do: GenServer.call(__MODULE__, {:tx, fun}, 15_000)

  @impl true
  def init(nil) do
    conn = DB.open()
    :ok = Backend.DB.Migrator.run(conn)
    {:ok, %{conn: conn}}
  end

  @impl true
  def handle_call({:tx, fun}, _from, %{conn: conn} = state) do
    :ok = Sqlite3.execute(conn, "BEGIN IMMEDIATE")

    try do
      result = fun.(conn)
      :ok = Sqlite3.execute(conn, "COMMIT")
      {:reply, {:ok, result}, state}
    rescue
      e ->
        _ = Sqlite3.execute(conn, "ROLLBACK")
        {:reply, {:error, e}, state}
    catch
      kind, reason ->
        _ = Sqlite3.execute(conn, "ROLLBACK")
        {:reply, {:error, {kind, reason}}, state}
    end
  end
end
