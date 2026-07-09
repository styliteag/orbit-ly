defmodule OrbitlyWeb.PageController do
  use OrbitlyWeb, :controller

  def home(conn, _params) do
    if conn.assigns[:current_user] do
      redirect(conn, to: ~p"/links")
    else
      redirect(conn, to: ~p"/sign-in")
    end
  end
end
