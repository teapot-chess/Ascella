defmodule Ascella.Sweep202611bTest do
  @moduledoc "The fixes of the second November sweep."

  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Ascella.{Context, Installer, Paths}
  alias AscellaWeb.Words

  @root Path.expand("../..", __DIR__)

  describe "programs left in the data folder by an older Linux service" do
    setup do
      tmp = Path.expand("ascella-adopt-#{System.unique_integer([:positive])}", System.tmp_dir!())
      data = Path.join(tmp, "data")
      programs = Path.join(tmp, "programs")
      File.mkdir_p!(Path.join(data, "programs/openpairings"))
      File.write!(Path.join(data, "programs/openpairings/VERSION"), "1.0.0\n")

      old_data = Application.get_env(:ascella, :data_dir)
      Application.put_env(:ascella, :data_dir, data)
      Application.put_env(:ascella, :programs_dir, programs)

      on_exit(fn ->
        Application.put_env(:ascella, :data_dir, old_data)
        Application.delete_env(:ascella, :programs_dir)
        File.rm_rf(tmp)
      end)

      %{data: data, programs: programs}
    end

    test "are moved to the programs folder", %{data: data, programs: programs} do
      assert Paths.adopt_old_programs() == :moved
      assert File.read!(Path.join(programs, "openpairings/VERSION")) == "1.0.0\n"
      refute File.exists?(Path.join(data, "programs"))
    end

    test "also when the new version already made an empty programs folder", %{
      programs: programs
    } do
      File.mkdir_p!(programs)
      assert Paths.adopt_old_programs() == :moved
      assert File.regular?(Path.join(programs, "openpairings/VERSION"))
    end

    test "but a programs folder in use is left alone", %{data: data, programs: programs} do
      File.mkdir_p!(Path.join(programs, "alnasl"))
      assert {:error, _} = Paths.adopt_old_programs()
      assert File.dir?(Path.join(programs, "alnasl"))
      assert File.dir?(Path.join(data, "programs/openpairings"))
    end

    @tag :unix
    test "and the data folder loses the execute bit for everyone", %{data: data} do
      if match?({:unix, _}, :os.type()) do
        File.chmod!(data, 0o751)
        assert Paths.adopt_old_programs() == :moved
        assert Bitwise.band(File.stat!(data).mode, 0o777) == 0o750
      end
    end

    test "nothing happens without a programs folder of its own" do
      Application.delete_env(:ascella, :programs_dir)
      assert Paths.adopt_old_programs() == :nothing
    end

    test "update.sh does not take an empty programs folder for one in use" do
      script = File.read!(Path.join(@root, "rel/linux/update.sh"))
      assert script =~ ~s(rmdir "$PROGRAMS_DIR")
    end
  end

  describe "a Windows program the launcher could not start" do
    test "names the program and the Windows error, not Ascella.exe" do
      ctx = %Context{
        family: :windows,
        starter: "C:\\Users\\x\\AppData\\Local\\AscellaApp\\current\\Ascella.exe",
        runner: Ascella.Sweep202611bTest.Refused
      }

      assert {:error, {:not_started, "Alnasl.exe", 5} = reason} =
               Installer.start_detached(ctx, "C:\\Programs\\Alnasl\\Alnasl.exe")

      assert Words.reason(reason) =~ "Alnasl.exe"
      assert Words.reason({:not_started, "Alnasl.exe", 2}) =~ "error 2"
    end
  end

  test "ascella.sh open says what to do when the browser shows no page" do
    script = File.read!(Path.join(@root, "rel/linux/ascella.sh"))
    assert script =~ "open --print"
    assert script =~ "If it shows no page"
  end
end

defmodule Ascella.Sweep202611bTest.Refused do
  @moduledoc false
  # The launcher's `--start` answering ERROR_ACCESS_DENIED.
  def cmd(_launcher, ["--start" | _args], _opts), do: {"", 5}
end
