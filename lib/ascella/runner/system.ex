defmodule Ascella.Runner.System do
  @moduledoc """
  The real runner: a port per command, with a missing program as exit status
  127 instead of a crash, and a program that does not finish as exit status
  124 (`timeout`'s own number) instead of a wait that never ends. The deadline
  is `opts[:timeout]` in milliseconds; `Ascella.Runner.run/4` always sets one.

  A program that outlives its deadline is killed, with what it started: the
  page says "nothing was changed after that point" and unlocks the app, and a
  root `sh install.sh` still running behind that sentence, next to the one the
  second click starts, would be the opposite of true.
  """
  @behaviour Ascella.Runner

  @default_timeout 300_000

  @impl true
  def cmd(program, args, opts) do
    exe = if File.regular?(program), do: program, else: System.find_executable(program)

    if exe,
      do: bounded(exe, args, opts, Keyword.get(opts, :timeout, @default_timeout)),
      else: {"#{program}: not found", 127}
  rescue
    error -> {Exception.message(error), 126}
  end

  # The port is opened here, in the caller, and read here, with the deadline
  # as the `receive`'s own. Opening can fail (no processes or file handles to
  # spare, for a moment; arguments that are not strings): that is an answer,
  # not a reason for the process that looks every few seconds whether the apps
  # are running to die, which once took Ascella down with it.
  defp bounded(exe, args, opts, timeout) do
    port = Port.open({:spawn_executable, exe}, port_options(args, opts))
    os_pid = port |> Port.info(:os_pid) |> os_pid()
    deadline = System.monotonic_time(:millisecond) + timeout
    collect(port, os_pid, {exe, timeout}, deadline, [])
  rescue
    error -> {"#{Path.basename(exe)}: #{Exception.message(error)}", 126}
  end

  defp port_options(args, opts) do
    base = [
      :binary,
      :exit_status,
      :stderr_to_stdout,
      :hide,
      args: Enum.map(args, &to_string_arg/1)
    ]

    base
    |> then(&if opts[:cd], do: [{:cd, to_charlist(opts[:cd])} | &1], else: &1)
    |> then(&if opts[:env], do: [{:env, env(opts[:env])} | &1], else: &1)
  end

  # `System.cmd`'s own complaint about an argument that is not a string, kept.
  defp to_string_arg(arg) when is_binary(arg), do: arg

  defp to_string_arg(arg),
    do: raise(ArgumentError, "all arguments for commands must be binaries, got: #{inspect(arg)}")

  defp env(env) do
    for {name, value} <- env do
      {to_charlist(name), if(value, do: to_charlist(value), else: false)}
    end
  end

  defp os_pid({:os_pid, pid}), do: pid
  defp os_pid(_gone), do: nil

  defp collect(port, os_pid, {exe, timeout} = what, deadline, acc) do
    left = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} ->
        collect(port, os_pid, what, deadline, [acc | data])

      {^port, {:exit_status, status}} ->
        {IO.iodata_to_binary(acc), status}
    after
      left ->
        kill(os_pid)
        if Port.info(port), do: Port.close(port)
        flush(port)

        {"#{Path.basename(exe)}: no answer within #{div(timeout, 1000)} seconds", 124}
    end
  end

  defp flush(port) do
    receive do
      {^port, _message} -> flush(port)
    after
      0 -> :ok
    end
  end

  # The program and what it started. A child that was started in its own
  # session escapes this; the common case (a shell script and the tools it
  # runs) does not.
  defp kill(nil), do: :ok

  defp kill(os_pid) do
    pid = Integer.to_string(os_pid)

    case :os.type() do
      {:win32, _} ->
        run("taskkill", ["/T", "/F", "/PID", pid])

      _unix ->
        run("pkill", ["-KILL", "-P", pid])
        run("kill", ["-KILL", pid])
    end
  end

  defp run(program, args) do
    case System.find_executable(program) do
      nil -> :ok
      exe -> System.cmd(exe, args, stderr_to_stdout: true)
    end
  rescue
    _no_such_thing -> :ok
  end
end
