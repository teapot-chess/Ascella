defmodule Ascella.Access do
  @moduledoc """
  The key that lets a browser use Ascella's page, for the Linux service.

  On Linux Ascella runs as root and listens on 127.0.0.1, and any process on
  the box can reach 127.0.0.1: another login, the service account of a sister
  program after it was compromised. The `LocalOnly` check and the CSRF token
  stop other *websites*; a local process fetches the page, takes the token and
  the cookie, and presses Install, Update, Stop, or "remove with its data" as
  root. So the service has a secret, per start:

    * at start-up (`start/0`, before the endpoint) a random key is written to
      `ASCELLA_TOKEN_FILE` (`/run/ascella/token` in the service unit), mode
      0600, owned by the user `ASCELLA_RUN_AS` names when there is one. Root
      and the desktop user can read it; nobody else on the box can;
    * the way in is the key, which `ascella.sh open` hands to the page: in
      a form posted to `/access` from a page only its owner can read (a key
      on a command line is one `ps` shows to every account), or as a link
      `/?k=<key>` that `ascella.sh open --print` prints for pasting. The page takes the key, puts a signed
      marker in the session cookie (the signing secret is root's) and redirects
      to the same address without it, so the key is neither in the history nor
      in a log of the next request;
    * every page and every LiveView mount (`AscellaWeb.AccessGate`) wants that
      marker, and a request without it gets a 403 that says how to get in.

  The marker is a hash of the key. The key is stable for the boot: a start
  that finds the key file it left (the unit's `RuntimeDirectoryPreserve=yes`
  keeps `/run/ascella` across restarts, and the reboot clears it) keeps the
  same key, so the open tab of the Setup page survives Ascella's own update
  instead of landing on a 403. A reboot, or a file that is gone or not a key,
  makes a new one.

  Where `ASCELLA_TOKEN_FILE` is not set - a terminal start on Linux, where
  Ascella is the user's own - none of this is on and nothing changes.

  Windows and macOS (where another account on a shared PC can reach
  `localhost:4090` as well) have the same gate behind a flag that is off by
  default, `ASCELLA_LOCAL_KEY=1` (`config :ascella, local_key: true`): the key
  is then the per-start secret the launcher already hands the program in
  `ASCELLA_LAUNCHER_TOKEN`, and the launcher has to open the page with
  `/?k=<that secret>` (or post it to `/access`). It stays off until the C and
  Swift launchers do that, since a launcher that does not would lock its own
  user out.
  """

  require Logger

  @key {__MODULE__, :token}

  @doc """
  Makes the key and its file, when `:access_token_file` is configured (or, with
  the `:local_key` flag, takes the launcher's per-start secret). Always `:ok`.
  """
  def start do
    case Application.get_env(:ascella, :access_token_file) do
      path when is_binary(path) and path != "" ->
        token = reuse(path) || mint()
        :persistent_term.put(@key, token)
        publish(path, token)

      _off ->
        launcher_key()
    end

    :ok
  end

  defp mint, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  # The key of this boot, when the file of the last start is still there: a
  # plain file, and a key as long as the ones made here.
  defp reuse(path) do
    with {:ok, %File.Stat{type: :regular}} <- File.lstat(path),
         {:ok, text} <- File.read(path),
         token = String.trim(text),
         true <- byte_size(token) == 43 and token =~ ~r/^[A-Za-z0-9_-]+$/ do
      token
    else
      _no -> nil
    end
  end

  # Windows and macOS, flag on: the launcher's own secret is the key.
  defp launcher_key do
    secret = System.get_env("ASCELLA_LAUNCHER_TOKEN")

    if Application.get_env(:ascella, :local_key, false) and is_binary(secret) and
         byte_size(secret) >= 16 do
      :persistent_term.put(@key, secret)
    else
      :persistent_term.erase(@key)
    end
  end

  @doc "Whether the page wants a key."
  def required?, do: :persistent_term.get(@key, nil) != nil

  @doc "Whether `given` is this start's key."
  def valid?(given) when is_binary(given) do
    case :persistent_term.get(@key, nil) do
      nil -> false
      token -> Plug.Crypto.secure_compare(given, token)
    end
  end

  def valid?(_other), do: false

  @doc "What the session holds once the key was shown: not the key, a hash of it."
  def marker do
    case :persistent_term.get(@key, nil) do
      nil ->
        nil

      token ->
        Base.url_encode64(:crypto.hash(:sha256, "ascella-access:" <> token), padding: false)
    end
  end

  @doc "Whether a session's marker is this start's."
  def granted?(given) when is_binary(given) do
    case marker() do
      nil -> false
      marker -> Plug.Crypto.secure_compare(given, marker)
    end
  end

  def granted?(_other), do: false

  # Created closed, then filled: the key is never in a file others can read.
  defp publish(path, token) do
    File.mkdir_p(Path.dirname(path))
    File.rm(path)

    with :ok <- File.touch(path),
         :ok <- File.chmod(path, 0o600),
         :ok <- hand_over(path),
         :ok <- File.write(path, token <> "\n") do
      :ok
    else
      error ->
        Logger.error(
          "Ascella could not write its key to #{path} (#{inspect(error)}). " <>
            "The page will turn everyone away until that is fixed."
        )
    end
  end

  # To the desktop user the service is configured for, so that user can read
  # it without being root. A user the system does not know leaves it root's.
  defp hand_over(path) do
    case System.get_env("ASCELLA_RUN_AS") do
      user when user in [nil, ""] ->
        :ok

      user ->
        case System.cmd("chown", ["--", user, path], stderr_to_stdout: true) do
          {_out, 0} ->
            :ok

          {out, _status} ->
            Logger.warning(
              "Ascella could not give its key file to #{user} (#{String.trim(out)}); " <>
                "it stays readable by root only."
            )

            :ok
        end
    end
  rescue
    _no_chown -> :ok
  end
end
