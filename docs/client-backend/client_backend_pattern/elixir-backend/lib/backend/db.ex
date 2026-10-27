defmodule Backend.DB do
  @moduledoc """
  Thin, auditable wrapper over Exqlite.Sqlite3. Raw parameterized SQL only;
  the SQL on the page is the SQL executed.

  Connection topology (mirrors the Go project):
    - writes: exactly one connection, owned by the Backend.DB.Writer
      GenServer; every write transaction is BEGIN IMMEDIATE;
    - reads: a fresh connection per call (`with_read/1`). Opening a SQLite
      connection is microseconds; at personal-server load a pool is not
      worth its code. Reads run concurrently with the writer under WAL.

  Requires exqlite ~> 0.27 (bind/2). Older exqlite used bind(conn, stmt,
  args); adjust if you pin an older version.
  """
  alias Exqlite.Sqlite3

  def path, do: Application.fetch_env!(:backend, :db_path)

  @doc "Open a connection with the reference pragmas applied."
  def open do
    {:ok, conn} = Sqlite3.open(path())
    :ok = Sqlite3.execute(conn, "PRAGMA busy_timeout = 5000")
    :ok = Sqlite3.execute(conn, "PRAGMA journal_mode = WAL")
    :ok = Sqlite3.execute(conn, "PRAGMA synchronous = NORMAL")
    :ok = Sqlite3.execute(conn, "PRAGMA foreign_keys = ON")
    conn
  end

  @doc "Run `fun` with a read connection; always closed afterwards."
  def with_read(fun) do
    conn = open()

    try do
      fun.(conn)
    after
      Sqlite3.close(conn)
    end
  end

  @doc """
  Execute SQL with `?1, ?2, ...` parameters; return rows as maps keyed by
  column name. Works for SELECT and for INSERT/UPDATE/DELETE ... RETURNING.
  """
  def query(conn, sql, params \\ []) do
    {:ok, stmt} = Sqlite3.prepare(conn, sql)
    :ok = Sqlite3.bind(stmt, params)
    {:ok, cols} = Sqlite3.columns(conn, stmt)
    {:ok, rows} = Sqlite3.fetch_all(conn, stmt)
    :ok = Sqlite3.release(conn, stmt)
    Enum.map(rows, fn row -> cols |> Enum.zip(row) |> Map.new() end)
  end

  @doc "Execute SQL that returns nothing of interest."
  def execute(conn, sql, params \\ []) do
    {:ok, stmt} = Sqlite3.prepare(conn, sql)
    :ok = Sqlite3.bind(stmt, params)
    step_all(conn, stmt)
    :ok = Sqlite3.release(conn, stmt)
    :ok
  end

  defp step_all(conn, stmt) do
    case Sqlite3.step(conn, stmt) do
      {:row, _} -> step_all(conn, stmt)
      :done -> :ok
    end
  end
end
