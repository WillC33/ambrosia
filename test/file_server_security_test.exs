defmodule Ambrosia.FileServerSecurityTest do
  @moduledoc """
  Comprehensive security test suite for FileServer path traversal protection.
  """

  use ExUnit.Case, async: false
  alias Ambrosia.{FileServer, Request}

  @test_root Path.expand("./test_root")

  setup_all do
    # Create test directory structure
    File.rm_rf!(@test_root)
    File.mkdir_p!(@test_root)

    # Create test files
    File.write!(Path.join(@test_root, "index.gmi"), "# Welcome")
    File.write!(Path.join(@test_root, "about.txt"), "About page")
    File.write!(Path.join(@test_root, ".hidden"), "Hidden file")

    # Create subdirectories
    File.mkdir_p!(Path.join(@test_root, "blog"))
    File.write!(Path.join(@test_root, "blog/post1.gmi"), "# Blog Post")

    File.mkdir_p!(Path.join(@test_root, "docs"))
    File.write!(Path.join(@test_root, "docs/manual.txt"), "Manual")

    # Create a file with dots in name
    File.write!(Path.join(@test_root, "file.with.dots.txt"), "Content")

    on_exit(fn ->
      File.rm_rf!(@test_root)
    end)

    :ok
  end

  describe "path traversal attacks" do
    setup do
      config = %{root_dir: @test_root}
      {:ok, config: config}
    end

    test "blocks basic parent directory traversal", %{config: config} do
      attacks = [
        "../etc/passwd",
        "../../etc/passwd",
        "../../../etc/passwd",
        "../../../../etc/passwd",
        "../../../../../../../../../etc/passwd"
      ]

      for path <- attacks do
        request = %Request{path: path}
        # Changed: Now returns "Not found" to avoid information leakage
        assert {51, "Not found"} = FileServer.serve(request, config)
      end
    end

    test "blocks traversal with valid prefix", %{config: config} do
      # Try to access a valid file, then traverse
      attacks = [
        "blog/../../../etc/passwd",
        "docs/../../../etc/passwd",
        "./../../etc/passwd"
      ]

      for path <- attacks do
        request = %Request{path: path}
        # Changed: Now returns "Not found"
        assert {51, "Not found"} = FileServer.serve(request, config)
      end
    end

    test "blocks absolute path attempts", %{config: config} do
      attacks = [
        "/etc/passwd",
        "/root/.ssh/id_rsa",
        "/var/log/secure",
        "//etc/passwd"
      ]

      for path <- attacks do
        request = %Request{path: path}
        result = FileServer.serve(request, config)

        # These resolve to paths within root, so should be "not found"
        assert elem(result, 0) == 51

        # Double-check we didn't accidentally serve system files
        case result do
          {20, _, content} ->
            refute String.contains?(content, "root:x:")

          _ ->
            :ok
        end
      end
    end

    test "blocks directory traversal with obfuscation", %{config: config} do
      attacks = [
        "././../././../etc/passwd",
        "./../.././../etc/passwd"
      ]

      for path <- attacks do
        request = %Request{path: path}
        # Changed: Now returns "Not found"
        assert {51, "Not found"} = FileServer.serve(request, config)
      end
    end
  end

  describe "valid path handling" do
    setup do
      config = %{root_dir: @test_root}
      {:ok, config: config}
    end

    test "serves files in root directory", %{config: config} do
      # Only .gmi files are served now
      request = %Request{path: "index.gmi"}
      assert {20, "text/gemini", content} = FileServer.serve(request, config)
      assert content == "# Welcome"

      # .txt files are rejected
      request = %Request{path: "about.txt"}
      assert {59, "File type not supported"} = FileServer.serve(request, config)
    end

    test "serves files in subdirectories", %{config: config} do
      # .gmi files work
      request = %Request{path: "blog/post1.gmi"}
      assert {20, "text/gemini", content} = FileServer.serve(request, config)
      assert content == "# Blog Post"

      # .txt files are rejected
      request = %Request{path: "docs/manual.txt"}
      assert {59, "File type not supported"} = FileServer.serve(request, config)
    end

    test "handles dots in filenames correctly", %{config: config} do
      # .txt files are no longer supported, only .gmi files
      request = %Request{path: "file.with.dots.txt"}
      assert {59, "File type not supported"} = FileServer.serve(request, config)
    end

    test "serves index file for root when present", %{config: config} do
      request = %Request{path: "/"}
      assert {20, "text/gemini", content} = FileServer.serve(request, config)

      # Should serve index.gmi content, not directory listing
      assert content == "# Welcome"
    end

    test "serves directory listing when no index file", %{config: config} do
      # Remove index files temporarily
      index_path = Path.join(@test_root, "index.gmi")
      File.rename!(index_path, index_path <> ".bak")

      request = %Request{path: "/"}
      assert {20, "text/gemini", listing} = FileServer.serve(request, config)

      # Check listing contains expected files
      assert String.contains?(listing, "about.txt")
      assert String.contains?(listing, "blog/")
      assert String.contains?(listing, "docs/")
      assert String.contains?(listing, "# Index of")

      # Restore index file
      File.rename!(index_path <> ".bak", index_path)
    end

    test "serves directory listing for subdirectory", %{config: config} do
      request = %Request{path: "blog"}
      assert {20, "text/gemini", listing} = FileServer.serve(request, config)

      assert String.contains?(listing, "post1.gmi")
      # Parent directory link should be present
      assert String.contains?(listing, "Parent directory")
    end

    test "returns not found for missing files", %{config: config} do
      request = %Request{path: "nonexistent.txt"}
      assert {51, "Not found"} = FileServer.serve(request, config)
    end
  end

  describe "edge cases" do
    setup do
      config = %{root_dir: @test_root}
      {:ok, config: config}
    end

    test "handles empty path", %{config: config} do
      request = %Request{path: ""}
      # Empty path should serve root directory
      assert {20, "text/gemini", _listing} = FileServer.serve(request, config)
    end

    test "handles repeated slashes", %{config: config} do
      paths = [
        "//index.gmi",
        "blog//post1.gmi",
        "docs///manual.txt"
      ]

      for path <- paths do
        request = %Request{path: path}
        result = FileServer.serve(request, config)
        # Path.expand normalizes these, so they should work
        # .gmi files return 20, .txt files return 59
        assert elem(result, 0) in [20, 59]
      end
    end

    test "handles paths with trailing slashes", %{config: config} do
      request = %Request{path: "blog/"}
      assert {20, "text/gemini", listing} = FileServer.serve(request, config)
      assert String.contains?(listing, "post1.gmi")
    end
  end

  describe "directory listing security" do
    setup do
      config = %{root_dir: @test_root}
      {:ok, config: config}
    end

    test "doesn't expose parent directory traversal in listings", %{config: config} do
      request = %Request{path: "blog"}
      assert {20, "text/gemini", content} = FileServer.serve(request, config)

      # Should have parent link
      assert String.contains?(content, "Parent directory")
      refute String.contains?(content, "../../")

      # Links should be properly encoded
      lines = String.split(content, "\n")

      for line <- lines do
        if String.starts_with?(line, "=>") do
          refute String.contains?(line, "../..")
        end
      end
    end

    test "handles special characters in filenames", %{config: config} do
      # Create a subdirectory without index files for testing
      test_dir = Path.join(@test_root, "test_listing")
      File.mkdir_p!(test_dir)

      # Create a .gmi file with special characters (only .gmi files are served)
      special_file = Path.join(test_dir, "test file.gmi")
      File.write!(special_file, "content")

      request = %Request{path: "/test_listing"}
      assert {20, "text/gemini", listing} = FileServer.serve(request, config)

      # Check for encoded version
      assert String.contains?(listing, "test%20file.gmi")

      # Clean up
      File.rm_rf!(test_dir)
    end
  end

  describe "security with different root configurations" do
    test "blocks traversal with relative root" do
      config = %{root_dir: "./test_root"}
      request = %Request{path: "../etc/passwd"}
      # Changed: Now returns "Not found"
      assert {51, "Not found"} = FileServer.serve(request, config)
    end

    test "blocks traversal with absolute root" do
      config = %{root_dir: @test_root}
      request = %Request{path: "../etc/passwd"}
      # Changed: Now returns "Not found"
      assert {51, "Not found"} = FileServer.serve(request, config)
    end

    test "handles root with trailing slash" do
      config = %{root_dir: @test_root <> "/"}
      request = %Request{path: "index.gmi"}
      assert {20, "text/gemini", _} = FileServer.serve(request, config)

      # Also check traversal still blocked
      request = %Request{path: "../etc/passwd"}
      # Changed: Now returns "Not found"
      assert {51, "Not found"} = FileServer.serve(request, config)
    end
  end
end
