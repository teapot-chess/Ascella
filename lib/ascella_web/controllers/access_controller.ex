defmodule AscellaWeb.AccessController do
  @moduledoc """
  `POST /access`: where `ascella.sh open` hands the page its key without the
  key ever being on a command line. The script writes a small page, readable
  by its owner only, whose form posts the key here; a right key puts the
  session marker in the cookie (see `AscellaWeb.AccessGate`) and goes to `/`.
  A wrong one is the same 403 as a page without a key.
  """
  use AscellaWeb, :controller

  alias Ascella.Access

  def create(conn, %{"k" => key}) when is_binary(key) do
    if Access.valid?(key) do
      conn
      |> put_session("ascella_access", Access.marker())
      |> redirect(to: "/")
    else
      AscellaWeb.AccessGate.turn_away(conn)
    end
  end

  def create(conn, _params), do: AscellaWeb.AccessGate.turn_away(conn)
end
