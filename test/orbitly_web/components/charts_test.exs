defmodule OrbitlyWeb.ChartsTest do
  use OrbitlyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias OrbitlyWeb.Charts

  defp points(values) do
    Enum.with_index(values, fn value, index -> {Date.add(~D[2026-01-01], index), value} end)
  end

  describe "area_chart/1" do
    test "draws a line and an area over the points" do
      html =
        render_component(&Charts.area_chart/1, id: "chart", points: points([1, 5, 3]))

      assert html =~ ~s(id="chart")
      assert html =~ "<path"
      # area path closes back to the baseline
      assert html =~ " Z\""
      assert html =~ "url(#chart-fill)"
    end

    test "one hover column per point, labelled with its value" do
      html = render_component(&Charts.area_chart/1, id: "chart", points: points([2, 7]))

      assert html |> String.split("chart-hit") |> length() == 3
      assert html =~ "01 Jan 2026: 2 clicks"
      assert html =~ "02 Jan 2026: 7 clicks"
    end

    test "month granularity labels buckets by month" do
      html =
        render_component(&Charts.area_chart/1,
          id: "chart",
          points: [{~D[2026-01-01], 4}, {~D[2026-02-01], 9}],
          granularity: :month
        )

      assert html =~ "Jan 2026: 4 clicks"
      assert html =~ "Feb 2026: 9 clicks"
    end

    test "marks the running bucket as partial" do
      html =
        render_component(&Charts.area_chart/1,
          id: "chart",
          points: points([4, 4, 2]),
          partial_last: true
        )

      assert html =~ "03 Jan 2026: 2 clicks (so far)"
      # only the running bucket is marked; completed ones stay plain
      assert html |> String.split("(so far)") |> length() == 2
      assert html =~ "<title>02 Jan 2026: 4 clicks</title>"
      # dashed tail segment on top of the solid line
      assert html =~ ~s(stroke-dasharray="5 5")
    end

    test "a complete series has no partial marker" do
      html = render_component(&Charts.area_chart/1, id: "chart", points: points([4, 4, 2]))

      refute html =~ "so far"
    end

    test "survives an all-zero series without dividing by zero" do
      html = render_component(&Charts.area_chart/1, id: "chart", points: points([0, 0, 0]))

      assert html =~ "<path"
      refute html =~ "NaN"
    end

    test "renders nothing but the frame for an empty series" do
      html = render_component(&Charts.area_chart/1, id: "chart", points: [])

      assert html =~ ~s(id="chart")
      refute html =~ "chart-hit"
      refute html =~ "NaN"
    end
  end

  describe "bar_list/1" do
    test "scales the bars against the largest row" do
      html = render_component(&Charts.bar_list/1, rows: [{"a", 10}, {"b", 5}])

      assert html =~ "width: 100%"
      assert html =~ "width: 50%"
      assert html =~ "a"
      assert html =~ "b"
    end

    test "shows the empty text without rows" do
      html = render_component(&Charts.bar_list/1, rows: [], empty_text: "Nothing here.")

      assert html =~ "Nothing here."
    end
  end
end
