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
end
