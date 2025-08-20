defmodule Ambrosia.RequestTest do
  use ExUnit.Case, async: true
  alias Ambrosia.Request

  describe "parse/1" do
    test "parses valid gemini URL" do
      assert {:ok,
              %Request{
                scheme: "gemini",
                host: "example.com",
                port: 1965,
                path: "/test.gmi",
                query: nil
              }} = Request.parse("gemini://example.com/test.gmi\r\n")
    end

    test "parses URL with custom port" do
      assert {:ok,
              %Request{
                host: "example.com",
                port: 1234,
                path: "/"
              }} = Request.parse("gemini://example.com:1234/\r\n")
    end

    test "parses URL with query string" do
      assert {:ok,
              %Request{
                path: "/search",
                query: "term=elixir"
              }} = Request.parse("gemini://example.com/search?term=elixir\r\n")
    end

    test "handles root path" do
      assert {:ok, %Request{path: "/"}} =
               Request.parse("gemini://example.com\r\n")
    end

    test "handles trailing slash" do
      assert {:ok, %Request{path: "/dir/"}} =
               Request.parse("gemini://example.com/dir/\r\n")
    end

    test "rejects non-gemini URLs" do
      assert {:error, :invalid_scheme} =
               Request.parse("http://example.com/\r\n")
    end

    test "rejects URLs over 1024 bytes" do
      long_path = String.duplicate("a", 1100)

      assert {:error, :url_too_long} =
               Request.parse("gemini://example.com/#{long_path}\r\n")
    end

    test "rejects invalid port" do
      assert {:error, :invalid_port} =
               Request.parse("gemini://example.com:99999/\r\n")
    end

    test "rejects malformed URLs" do
      assert {:error, :invalid_url} =
               Request.parse("gemini://\r\n")
    end

    test "rejects URL without CRLF termination" do
      assert {:error, :missing_crlf} =
               Request.parse("gemini://example.com/test.gmi")

      assert {:error, :missing_crlf} =
               Request.parse("gemini://example.com/test.gmi\\n")

      assert {:error, :missing_crlf} = Request.parse("gemini://example.com/")
    end

    test "accepts only proper CRLF termination" do
      assert {:ok, %Request{}} = Request.parse("gemini://example.com/\r\n")

      assert {:error, :missing_crlf} =
               Request.parse("gemini://example.com/\\r\\n")

      assert {:error, :missing_crlf} = Request.parse("gemini://example.com/\\n")
      assert {:error, :missing_crlf} = Request.parse("gemini://example.com/")
    end
  end

  describe "safe_path?/1" do
    test "accepts normal paths" do
      req = %Request{path: "/normal/path.gmi"}
      assert Request.safe_path?(req)
    end

    test "accepts root path" do
      req = %Request{path: "/"}
      assert Request.safe_path?(req)
    end

    test "rejects path traversal attempts" do
      req = %Request{path: "/../etc/passwd"}
      refute Request.safe_path?(req)
    end

    test "rejects embedded traversal" do
      req = %Request{path: "/valid/../../../etc/passwd"}
      refute Request.safe_path?(req)
    end

    test "rejects double slashes" do
      req = %Request{path: "//etc/passwd"}
      # Should normalize to /etc/passwd
      assert Request.safe_path?(req)
    end
  end

  describe "valid_for_server?/2" do
    test "accepts localhost" do
      req = %Request{host: "localhost"}
      assert Request.valid_for_server?(req, %{})
    end

    test "accepts 127.0.0.1" do
      req = %Request{host: "127.0.0.1"}
      assert Request.valid_for_server?(req, %{})
    end

    test "accepts configured hostname" do
      req = %Request{host: "myserver.com"}
      assert Request.valid_for_server?(req, %{hostname: "myserver.com"})
    end

    test "rejects unknown hosts by default" do
      req = %Request{host: "unknown.com"}
      refute Request.valid_for_server?(req, %{})
    end
  end
end
