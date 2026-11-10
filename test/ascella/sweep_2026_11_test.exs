defmodule Ascella.Sweep202611Test do
  @moduledoc "The fixes of the 2026-11 sweep that have no better home."

  use ExUnit.Case, async: false

  alias Ascella.{Context, FakeGitHub, Fetch, Platform}
  alias Ascella.Runner.System, as: Real
  alias AscellaWeb.Words

  @root Path.expand("../..", __DIR__)
  @opts [plug: {Req.Test, Ascella.GitHub}]

  defp read(path), do: File.read!(Path.join(@root, path))

  describe "a command past its deadline" do
    @tag :unix
    test "is killed with what it started, not left running behind the sentence" do
      if match?({:unix, _}, :os.type()) do
        dir = Path.expand("ascella-kill-#{System.unique_integer([:positive])}", System.tmp_dir!())
        File.mkdir_p!(dir)
        on_exit(fn -> File.rm_rf(dir) end)
        pidfile = Path.join(dir, "pid")

        assert {message, 124} =
                 Real.cmd("sh", ["-c", "sleep 30 & echo $! > '#{pidfile}'; wait"], timeout: 500)

        assert message =~ "no answer"
        pid = pidfile |> File.read!() |> String.trim()
        assert gone?(pid, 40)
      end
    end

    test "still gives the output of one that finishes in time" do
      exe = System.find_executable("elixir") || System.find_executable("erl")
      assert {out, 0} = Real.cmd(exe, ["--version"], timeout: 60_000)
      assert out =~ "Erlang" or out =~ "Elixir"
    end
  end

  defp gone?(pid, tries) do
    {_out, status} = System.cmd("kill", ["-0", pid], stderr_to_stdout: true)

    cond do
      status != 0 ->
        true

      tries == 0 ->
        false

      true ->
        receive do
        after
          50 -> gone?(pid, tries - 1)
        end
    end
  end

  describe "a download" do
    setup do
      dir = Path.expand("ascella-dl-#{System.unique_integer([:positive])}", System.tmp_dir!())
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)
      {:ok, dir: dir}
    end

    test "of a checksum file that is absurdly large is stopped", %{dir: dir} do
      huge = String.duplicate("x", 2_000_000)

      FakeGitHub.serve(%{
        "Example/App" => %{version: "1.0.0", files: %{"app.zip" => "x"}, sums: huge}
      })

      assert {:error, :too_big} = Fetch.download("Example/App", "v1.0.0", "app.zip", dir, @opts)
      refute File.exists?(Path.join(dir, "app.zip"))
    end
  end

  test "a 32-bit machine has no build, instead of an x86_64 one that cannot run" do
    assert Platform.arch("armv7l-unknown-linux-gnueabihf", false) == "unsupported"
    assert Platform.arch("i686-pc-linux-gnu", false) == "unsupported"
    assert Platform.arch("x86_64-pc-linux-gnu", false) == "x86_64"
    assert Platform.arch("aarch64-unknown-linux-gnu", false) == "aarch64"
    assert Platform.arch("win32", false) == "x86_64"
  end

  describe "the words for a failure" do
    test "are words, not Elixir terms" do
      for reason <- [
            :no_start,
            :no_install_script,
            :no_update_script,
            :no_pid,
            :unreadable_release,
            :unknown,
            :manual,
            {:swap, :eacces},
            {:unsafe_zip_entry, "../x"},
            {:bad_zip, :x},
            :nothing_to_show,
            :eacces,
            :enoent,
            :no_unzip
          ] do
        text = Words.reason(reason)
        refute text =~ ~r/^[:{]/, "#{inspect(reason)} came out as #{text}"
      end
    end

    test "a program that stopped with a code says what it said" do
      assert Words.reason({:exit, "sh", 1, "unzip: cannot find\n"}) =~ "cannot find"
      assert Words.reason({:exit, "sh", 1, ""}) =~ "code 1"
    end
  end

  test "the Linux service offers no shortcuts it cannot place" do
    ctx = %Context{family: :linux, service?: true, desktop: "/nonexistent", gsettings: true}
    assert Ascella.Launchers.Linux.kinds(ctx, %{exec: "/bin/true"}) == []

    assert [:menu | _] =
             Ascella.Launchers.Linux.kinds(%{ctx | service?: false}, %{exec: "/bin/true"})
  end

  describe "the Linux scripts" do
    test "ascella.sh open does not put the key on a command line" do
      script = read("rel/linux/ascella.sh")
      assert script =~ "/access"
      refute script =~ ~s(xdg-open "$url")
      assert script =~ "umask 077"
    end

    test "install.sh checks its options" do
      install = read("rel/linux/install.sh")
      assert install =~ ~s([ $# -ge 2 ])
      assert install =~ "that is not a version number"
    end
  end

  test "the secret key base file is made private before the secret goes in" do
    runtime = read("config/runtime.exs")
    {empty, _} = :binary.match(runtime, ~s[File.write!(secret_file, "")])
    {secret, _} = :binary.match(runtime, "File.write!(secret_file, secret)")
    assert empty < secret
  end
end
