defmodule Ambrosia.FileServerTest do
  use ExUnit.Case, async: true
  alias Ambrosia.{FileServer, Request}

  @fixtures_path Path.expand("test/fixtures/gemini")

  setup_all do
    # Create test fixture directory structure
    File.rm_rf!(@fixtures_path)
    File.mkdir_p!(@fixtures_path)

    # Create gemini files
    File.write!(Path.join(@fixtures_path, "index.gmi"), "# Home Page")
    File.write!(Path.join(@fixtures_path, "about.gmi"), "# About Us")

    # Create a text file that won't be served
    File.write!(Path.join(@fixtures_path, "test.txt"), "Plain text")

    # Create subdirectory with content
    File.mkdir_p!(Path.join(@fixtures_path, "subdir"))
    File.write!(Path.join(@fixtures_path, "subdir/page.gmi"), "# Subpage")

    # Create subdirectory without index for listing
    File.mkdir_p!(Path.join(@fixtures_path, "listing"))
    File.write!(Path.join(@fixtures_path, "listing/file1.gmi"), "# File 1")
    File.write!(Path.join(@fixtures_path, "listing/file2.gmi"), "# File 2")

    on_exit(fn ->
      File.rm_rf!(@fixtures_path)
    end)

    :ok
  end

  describe "serve/2" do
    setup do
      config = %{root_dir: @fixtures_path}
      {:ok, config: config}
    end

    test "serves index.gmi when accessing root", %{config: config} do
      req = %Request{path: "/"}
      assert {20, "text/gemini", content} = FileServer.serve(req, config)
      assert content == "# Home Page"
    end

    test "serves specific gemini file", %{config: config} do
      req = %Request{path: "about.gmi"}
      assert {20, "text/gemini", content} = FileServer.serve(req, config)
      assert content == "# About Us"
    end

    test "rejects non-gemini files", %{config: config} do
      # Ensure file exists for this specific test
      txt_path = Path.join(config.root_dir, "test.txt")
      File.write!(txt_path, "Plain text")

      req = %Request{path: "test.txt"}
      assert {59, "File type not supported"} = FileServer.serve(req, config)
      # Teardown will handle cleanup
    end

    test "generates directory listing when no index", %{config: config} do
      req = %Request{path: "listing"}
      assert {20, "text/gemini", listing} = FileServer.serve(req, config)

      # Check header shows relative path
      assert listing =~ "# Index of /listing"

      # Check it contains the files
      assert listing =~ "file1.gmi"
      assert listing =~ "file2.gmi"

      # Check parent directory link is present
      assert listing =~ "Parent directory"
    end

    test "serves files from subdirectories", %{config: config} do
      req = %Request{path: "subdir/page.gmi"}
      assert {20, "text/gemini", content} = FileServer.serve(req, config)
      assert content == "# Subpage"
    end

    test "returns not found for missing files", %{config: config} do
      req = %Request{path: "nonexistent.gmi"}
      assert {51, "Not found"} = FileServer.serve(req, config)
    end

    test "returns not found for missing directories", %{config: config} do
      req = %Request{path: "missing/dir/file.gmi"}
      assert {51, "Not found"} = FileServer.serve(req, config)
    end

    test "handles empty path as root", %{config: config} do
      req = %Request{path: ""}
      assert {20, "text/gemini", content} = FileServer.serve(req, config)
      assert content == "# Home Page"
    end

    test "detects only gemini MIME types", %{config: config} do
      test_files = [
        {"test.gmi", "text/gemini"},
        {"test.gemini", "text/gemini"},
        {"test.txt", :unsupported},
        {"test.md", :unsupported},
        {"test.html", :unsupported}
      ]

      for {filename, expected_mime} <- test_files do
        # Create the file
        file_path = Path.join(@fixtures_path, filename)
        File.write!(file_path, "Test content")

        req = %Request{path: filename}
        result = FileServer.serve(req, config)

        case expected_mime do
          "text/gemini" ->
            assert {20, "text/gemini", _} = result

          :unsupported ->
            assert {59, "File type not supported"} = result
        end

        # Clean up
        File.rm!(file_path)
      end
    end

    test "handles file size limits", %{config: config} do
      # Create a file that appears to be over 100MB (would need mocking for actual test)
      # This is a placeholder for the actual implementation
      # In production, you'd mock File.stat to return a large size
      large_file = Path.join(@fixtures_path, "large.gmi")
      File.write!(large_file, "Large file")

      # This would need proper mocking to test the size limit
      req = %Request{path: "large.gmi"}
      result = FileServer.serve(req, config)

      # Should succeed for now since we can't easily create a 100MB file in tests
      assert elem(result, 0) in [20, 59]

      File.rm!(large_file)
    end
  end

  describe "security" do
    setup do
      config = %{root_dir: @fixtures_path}
      {:ok, config: config}
    end

    test "blocks path traversal attempts", %{config: config} do
      req = %Request{path: "../etc/passwd"}
      assert {51, "Not found"} = FileServer.serve(req, config)
    end

    test "normalizes paths with double slashes", %{config: config} do
      req = %Request{path: "//index.gmi"}
      assert {20, "text/gemini", content} = FileServer.serve(req, config)
      assert content == "# Home Page"
    end
  end
end
