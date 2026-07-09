defmodule OrbitlyWeb.AuthRateLimitTest do
  use OrbitlyWeb.ConnCase, async: false

  alias Orbitly.Shortener.RateLimiter

  setup do
    RateLimiter.clear_all()
    :ok
  end

  test "throttles repeated credential POSTs from one IP with 429", %{conn: _conn} do
    submit = fn ->
      build_conn()
      |> Map.put(:remote_ip, {203, 0, 113, 90})
      |> post("/auth/user/password/sign_in", %{
        "user" => %{"email" => "nobody@example.com", "password" => "wrong"}
      })
    end

    # 10 attempts pass the limiter (the auth strategy itself rejects them),
    # the 11th is blocked before reaching it
    statuses = for _ <- 1..10, do: submit.().status
    refute 429 in statuses

    assert submit.().status == 429
  end

  test "GET requests to auth routes are not throttled", %{conn: _conn} do
    for _ <- 1..15 do
      conn = get(build_conn(), "/sign-in")
      assert conn.status == 200
    end
  end

  test "a spoofed X-Forwarded-For left entry does not grant a fresh bucket", %{conn: _conn} do
    submit = fn i ->
      build_conn()
      |> Map.put(:remote_ip, {10, 0, 0, 1})
      |> put_req_header("x-forwarded-for", "1.2.3.#{i}, 198.51.100.42")
      |> post("/auth/user/password/sign_in", %{
        "user" => %{"email" => "nobody@example.com", "password" => "wrong"}
      })
    end

    statuses = for i <- 1..10, do: submit.(i).status
    refute 429 in statuses

    # rotating the spoofable left entry must not reset the counter
    assert submit.(999).status == 429
  end
end
