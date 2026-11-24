defmodule Ascella.Paths do
  @moduledoc """
  Where Ascella keeps its own things: one directory (`config :ascella,
  :data_dir`, `ASCELLA_DATA`). The downloads it has verified, the copies of
  programs it put in place itself (a portable zip, a Linux zip), and the
  request file for its own update. Never any managed app's data: those
  belong to the apps, and `Ascella.Guard` keeps it that way.
  """

  require Logger

  def data, do: ensure(Application.fetch_env!(:ascella, :data_dir))
  def downloads, do: ensure(Path.join(data(), "downloads"))

  @doc "Where Ascella unpacks programs that have no installer of their own here."
  def programs do
    case Application.get_env(:ascella, :programs_dir) do
      nil -> ensure(Path.join(data(), "programs"))
      dir -> ensure(dir)
    end
  end

  @doc """
  Moves the programs of an older Linux service (`<data>/programs`) to
  `programs_dir` (`ASCELLA_PROGRAMS`), and takes the "execute for everyone"
  bit that older version put on the data folder off again. Run at every start,
  before anything looks at the programs.

  `update.sh` does the same, but the `update.sh` that runs an update is the
  one already installed: a box updated from 0.4 by its Setup page got the new
  unit (and its `ASCELLA_PROGRAMS`) from the old script, which knew nothing of
  any move. Its programs stayed where nothing looked any more, and the
  program's first start made an empty `programs_dir` that the next
  `update.sh` took for one in use. An empty one is therefore no reason to
  stay put. A full one is: then nothing is touched and the log says so.

  `:moved`, `:nothing` or `{:error, reason}`; never raises.
  """
  def adopt_old_programs do
    with dir when is_binary(dir) <- Application.get_env(:ascella, :programs_dir),
         data when is_binary(data) <- Application.get_env(:ascella, :data_dir),
         old = Path.join(data, "programs"),
         true <- Path.expand(old) != Path.expand(dir),
         {:ok, %File.Stat{type: :directory}} <- File.lstat(old) do
      move_programs(old, dir, data)
    else
      _nothing_old -> :nothing
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp move_programs(old, dir, data) do
    with :ok <- clear_way(dir),
         :ok <- File.mkdir_p(Path.dirname(dir)),
         :ok <- File.rename(old, dir) do
      close_data(data)
      Logger.info("Ascella moved its programs from #{old} to #{dir}.")
      :moved
    else
      {:error, reason} = error ->
        Logger.warning(
          "Ascella's programs are still in #{old}, and #{dir} is where it looks now " <>
            "(#{inspect(reason)}). Move them there with the service stopped."
        )

        error
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp clear_way(dir) do
    case File.lstat(dir) do
      {:error, :enoent} -> :ok
      {:ok, %File.Stat{type: :directory}} -> File.rmdir(dir)
      {:ok, %File.Stat{type: type}} -> {:error, {:in_the_way, type}}
      {:error, reason} -> {:error, reason}
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp close_data(data) do
    case File.stat(data) do
      {:ok, %File.Stat{mode: mode}} when Bitwise.band(mode, 0o001) != 0 ->
        File.chmod(data, Bitwise.band(mode, 0o7776))

      _closed ->
        :ok
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp ensure(dir) do
    File.mkdir_p!(dir)
    dir
  end
end
