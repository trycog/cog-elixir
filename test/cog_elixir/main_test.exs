defmodule CogElixir.MainTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  test "indexes a files manifest and continues past failures" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "cog-elixir-main-#{System.unique_integer([:positive])}")

    try do
      File.mkdir_p!(Path.join(tmp_dir, "lib"))

      File.write!(
        Path.join(tmp_dir, "mix.exs"),
        "defmodule Demo.MixProject do\n  use Mix.Project\n  def project, do: [app: :demo]\nend\n"
      )

      good_file = Path.join(tmp_dir, "lib/good.ex")
      bad_file = Path.join(tmp_dir, "lib/bad.ex")
      missing_file = Path.join(tmp_dir, "lib/missing.ex")
      output_file = Path.join(tmp_dir, "index.scip")

      File.write!(good_file, "defmodule Demo.Good do\n  def hello(name), do: name\nend\n")
      File.write!(bad_file, "defmodule Demo.Bad do\n  def broken( do\nend\n")

      stderr =
        capture_io(:stderr, fn ->
          File.cd!(tmp_dir, fn ->
            CogElixir.main(["--output", output_file, good_file, bad_file, missing_file])
          end)
        end)

      assert File.exists?(output_file)
      output = File.read!(output_file)
      assert output != <<>>
      assert output =~ "Demo.Good"
      assert stderr =~ "Warning: skipping missing file"
    after
      File.rm_rf(tmp_dir)
    end
  end

  test "indexes eex and heex files through main entrypoint" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "cog-elixir-templates-#{System.unique_integer([:positive])}")

    try do
      File.mkdir_p!(Path.join(tmp_dir, "lib"))

      File.write!(
        Path.join(tmp_dir, "mix.exs"),
        "defmodule Demo.MixProject do\n  use Mix.Project\n  def project, do: [app: :demo]\nend\n"
      )

      eex_file = Path.join(tmp_dir, "lib/show.html.eex")
      heex_file = Path.join(tmp_dir, "lib/table.heex")
      output_file = Path.join(tmp_dir, "index.scip")

      File.write!(eex_file, "<%= foo(bar) %>\n<%= @name %>\n")

      File.write!(
        heex_file,
        ~S|<.table rows={@rows}><:col :let={row}>{row.name}</:col><div :for={item <- @items}>{item}</div></.table>| <>
          "\n"
      )

      File.cd!(tmp_dir, fn ->
        CogElixir.main(["--output", output_file, eex_file, heex_file])
      end)

      assert File.exists?(output_file)
      output = File.read!(output_file)
      assert output =~ "show.html.eex"
      assert output =~ "table.heex"
      assert output =~ "@name"
      assert output =~ ":col"
      assert output =~ "item"
    after
      File.rm_rf(tmp_dir)
    end
  end

  test "indexes nested slots and module components through main entrypoint" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "cog-elixir-phoenix-#{System.unique_integer([:positive])}")

    try do
      File.mkdir_p!(Path.join(tmp_dir, "lib"))

      File.write!(
        Path.join(tmp_dir, "mix.exs"),
        "defmodule Demo.MixProject do\n  use Mix.Project\n  def project, do: [app: :demo]\nend\n"
      )

      heex_file = Path.join(tmp_dir, "lib/components.heex")
      output_file = Path.join(tmp_dir, "index.scip")

      File.write!(
        heex_file,
        ~S|<.table rows={@rows}><:col :let={row}><MyAppWeb.CoreComponents.button kind={row.kind}>{row.label}</MyAppWeb.CoreComponents.button></:col><:action :let={action}><span :if={@show_actions}>{action.name}</span></:action></.table>| <>
          "\n"
      )

      File.cd!(tmp_dir, fn ->
        CogElixir.main(["--output", output_file, heex_file])
      end)

      assert File.exists?(output_file)
      output = File.read!(output_file)
      assert output =~ "components.heex"
      assert output =~ ":col"
      assert output =~ ":action"
      assert output =~ "CoreComponents"
      assert output =~ "button"
      assert output =~ "row"
      assert output =~ "action"
      assert output =~ "@show_actions"
    after
      File.rm_rf(tmp_dir)
    end
  end
end
