defmodule AscellaWeb.Locale do
  @moduledoc """
  English or Dutch. `?lang=nl` (or `en`) chooses and is remembered in the
  session; without a choice the browser's first language decides. The
  live page reads the same session, so the two never disagree.
  """
  import Plug.Conn

  @locales ~w(en nl)

  def locales, do: @locales

  # --- as a plug -----------------------------------------------------------------

  def init(opts), do: opts

  @doc """
  The language this request would get, for plugs that answer before this one
  runs (the 403 pages): `?lang=`, the session when it has been fetched, then
  the browser's own header.
  """
  def detect(conn) do
    conn = Plug.Conn.fetch_query_params(conn)
    chosen = conn.query_params["lang"]
    session = if Map.has_key?(conn.private, :plug_session), do: get_session(conn, "locale")

    cond do
      chosen in @locales -> chosen
      session in @locales -> session
      true -> from_header(get_req_header(conn, "accept-language"))
    end
  end

  def call(conn, _opts) do
    chosen = conn.params["lang"]

    locale =
      cond do
        chosen in @locales -> chosen
        get_session(conn, "locale") in @locales -> get_session(conn, "locale")
        true -> from_header(get_req_header(conn, "accept-language"))
      end

    Gettext.put_locale(AscellaWeb.Gettext, locale)

    conn
    |> put_session("locale", locale)
    |> assign(:locale, locale)
  end

  defp from_header([header | _]) do
    first = header |> String.split(",") |> List.first("") |> String.trim() |> String.downcase()
    if String.starts_with?(first, "nl"), do: "nl", else: "en"
  end

  defp from_header([]), do: "en"

  # --- in a live view --------------------------------------------------------------

  def on_mount(:default, _params, session, socket) do
    locale = if session["locale"] in @locales, do: session["locale"], else: "en"
    Gettext.put_locale(AscellaWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end
end
