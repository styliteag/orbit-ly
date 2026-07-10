defmodule OrbitlyWeb.UserSettingsLiveTest do
  use OrbitlyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Orbitly.Fixtures

  alias Orbitly.Accounts

  setup do
    %{user: registered_user_fixture()}
  end

  test "redirects anonymous visitors to sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/settings")
  end

  test "renders the change-password form", %{conn: conn, user: user} do
    {:ok, _view, html} = conn |> log_in(user) |> live(~p"/settings")

    assert html =~ "Change password"
    assert html =~ user.email
  end

  test "updates the password and triggers the re-login submit", %{conn: conn, user: user} do
    {:ok, view, _html} = conn |> log_in(user) |> live(~p"/settings")

    form =
      form(view, "#password-form", %{
        "current_password" => default_password(),
        "user" => %{
          "email" => user.email,
          "password" => "brand-new-password",
          "password_confirmation" => "brand-new-password"
        }
      })

    render_submit(form)

    # trigger_submit posts the form to /session for a fresh token
    assert Accounts.get_user_by_email_and_password(user.email, "brand-new-password")

    conn = follow_trigger_action(form, conn)
    assert redirected_to(conn) == ~p"/settings"

    conn = get(conn, ~p"/settings")
    assert html_response(conn, 200) =~ "Change password"
  end

  test "throttles repeated password-change attempts", %{conn: conn, user: user} do
    {:ok, view, _html} = conn |> log_in(user) |> live(~p"/settings")

    submit = fn ->
      view
      |> form("#password-form", %{
        "current_password" => "wrong-guess",
        "user" => %{
          "password" => "brand-new-password",
          "password_confirmation" => "brand-new-password"
        }
      })
      |> render_submit()
    end

    for _ <- 1..5, do: submit.()

    assert submit.() =~ "Too many attempts"
    assert Accounts.get_user_by_email_and_password(user.email, default_password())
  end

  test "shows an error for a wrong current password", %{conn: conn, user: user} do
    {:ok, view, _html} = conn |> log_in(user) |> live(~p"/settings")

    html =
      view
      |> form("#password-form", %{
        "current_password" => "totally-wrong",
        "user" => %{
          "password" => "brand-new-password",
          "password_confirmation" => "brand-new-password"
        }
      })
      |> render_submit()

    assert html =~ "is not valid"
    assert Accounts.get_user_by_email_and_password(user.email, default_password())
  end
end
