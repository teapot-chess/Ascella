defmodule Ascella.StartCommandTest do
  @moduledoc """
  How a Windows program is started (`Ascella.Installer.start_command/4`):
  through the launcher's `--start`, Ascella's own variables left behind,
  and never through WMI, which Symantec takes for ransomware.
  """

  use ExUnit.Case, async: true

  alias Ascella.{Context, Installer}

  @env %{
    "PORT" => "4090",
    "ASCELLA_DATA" => "C:\\Users\\x\\AppData\\Local\\AscellaData",
    "RELEASE_ROOT" => "C:\\x",
    "Path" => "C:\\Windows\\system32",
    "USERPROFILE" => "C:\\Users\\x"
  }

  @update "C:\\Users\\x\\AppData\\Local\\AlnaslApp\\Update.exe"

  test "with the launcher: Ascella.exe --start, the program and its arguments as given" do
    ctx = %Context{starter: "C:\\Users\\x\\AppData\\Local\\AscellaApp\\current\\Ascella.exe"}

    assert {starter, ["--start", @update, "start"], opts} =
             Installer.start_command(ctx, @update, ["start"], @env)

    assert starter == ctx.starter
    unset = Keyword.fetch!(opts, :env)
    assert {"PORT", nil} in unset
    assert {"ASCELLA_DATA", nil} in unset
    assert {"RELEASE_ROOT", nil} in unset
    refute List.keymember?(unset, "Path", 0)
    refute List.keymember?(unset, "USERPROFILE", 0)
  end

  test "without the launcher: Start-Process, quotes doubled, no WMI" do
    program = "C:\\Program Files\\O'Brien\\Alnasl.exe"

    assert {"powershell", ["-NoProfile", "-NonInteractive", "-EncodedCommand", encoded], opts} =
             Installer.start_command(%Context{starter: nil}, program, ["--x", "it's"], @env)

    script = encoded |> Base.decode64!() |> :unicode.characters_to_binary({:utf16, :little})

    assert script ==
             "Start-Process -FilePath 'C:\\Program Files\\O''Brien\\Alnasl.exe'" <>
               " -ArgumentList '\"--x\"','\"it''s\"'" <>
               " -WorkingDirectory 'C:\\Program Files\\O''Brien'"

    refute script =~ ~r/Win32_Process|CimMethod|WmiMethod/i
    assert {"PORT", nil} in Keyword.fetch!(opts, :env)
  end

  test "an empty starter is no starter" do
    assert {"powershell", _args, _opts} =
             Installer.start_command(%Context{starter: ""}, @update, [], @env)
  end
end
