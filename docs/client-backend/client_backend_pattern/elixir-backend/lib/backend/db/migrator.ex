defmodule Backend.DB.Migrator do
  @moduledoc """
  Applies priv/migrations/NNN_*.sql files, in order, whose numeric prefix
  exceeds PRAGMA user_version. Each file runs in one transaction together
  with the user_version bump. Same mechanism and same limitation as the Go
  project: statements are split on ";" at end of line, so keep migration
  files to plain DDL/DML (no trigger bodies containing semicolons).
  """
  alias Backend.DB
  alias Exqlite.Sqlite3

  def run(conn) do
    version = current_version(conn)

    migrations_dir()
    |> File.ls!()
    |> Enum.sort()
    |> Enum.each(fn name ->
      case Regex.run(~r/^(\d+)_.*\.sql$/, name) do
        [_, num] ->
          n = String.to_integer(num)
          if n > version, do: apply_file(conn, Path.join(migrations_dir(), name), n)

        nil ->
          :ok
      end
    end)

    :ok
  end

  defp migrations_dir, do: Application.app_dir(:backend, "priv/migrations")

  defp current_version(conn) do
    [%{"user_version" => v}] = DB.query(conn, "PRAGMA user_version")
    v
  end

  defp apply_file(conn, path, n) do
    statements =
      path
      |> File.read!()
      |> String.split(~r/;\s*\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.trim_trailing(&1, ";"))
      |> Enum.reject(&(&1 == ""))

    :ok = Sqlite3.execute(conn, "BEGIN IMMEDIATE")

    try do
      Enum.each(statements, &(:ok = DB.execute(conn, &1)))
      # PRAGMA takes no bound parameters; n comes from the filename regexp.
      :ok = Sqlite3.execute(conn, "PRAGMA user_version = #{n}")
      :ok = Sqlite3.execute(conn, "COMMIT")
    rescue
      e ->
        _ = Sqlite3.execute(conn, "ROLLBACK")
        reraise e, __STACKTRACE__
    end
  end
end
