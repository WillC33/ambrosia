**⚠️ WARNING: Currently, Ambrosia is preproduction software with known security limitations. 
Use only in trusted environments or for development purposes.**

# 🏛️ Ambrosia

A fault-tolerant, concurrent Gemini protocol server written in Elixir. Built for immortality on the BEAM. Ambrosia is designed for serving high-uptime
Capsules on the Geminispace.

## What is Ambrosia?

Ambrosia is a Gemini server that leverages the Erlang VM's legendary fault tolerance and concurrency to serve your Gemini capsule. It's designed to be simple to deploy, secure by default, and resilient under load. Whether you're running a personal capsule or hosting multiple sites, Ambrosia keeps serving.

## Features

- **Fault Tolerant**: Built on the BEAM VM with supervision trees - if something crashes, it restarts
- **Concurrent by Design**: Handles a ton of concurrent connections without breaking a sweat
- **Docker Ready**: Single container deployment with automatic certificate generation
- **Monitoring Built-in**: Prometheus metrics endpoint for observability
- **Minimal Resource Usage**: Runs comfortably on a Raspberry Pi hovering about 75-100MB memory
- **Gemtext Native**: Serves `.gmi` files with proper MIME types
- **Directory Listings**: Auto-generates navigable directory indices

## Quick Start

### Using Docker (Recommended)

```bash
# Create your content directory
mkdir -p gemini certs

# Create docker-compose.yml (see below)
# Add your .gmi files to ./gemini/

# Run it
HOSTNAME=your-domain.com docker-compose up -d
```

Basic `docker-compose.yml`:
```yaml
services:
  ambrosia:
    image: ghcr.io/willc33/ambrosia:latest
    ports:
      - "1965:1965"
    volumes:
      - ./gemini:/app/gemini:ro
      - ./certs:/certs:ro  # Optional: provide your own certs
    environment:
      - HOSTNAME=your-capsule.com
    restart: unless-stopped
```

That's it. Ambrosia will generate self-signed certificates if you don't provide them.
You are also welcome to use the compose files in the repository

### From Source

```bash
# Prerequisites: Elixir 1.15+, Erlang/OTP 25+
git clone https://codeberg.org/WillC33/ambrosia.git
cd ambrosia

# Install dependencies
mix deps.get

# Generate certificates
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout certs/key.pem -out certs/cert.pem \
  -days 365 -subj "/CN=localhost"

# Run in development
HOSTNAME=localhost mix run --no-halt

# Or build a release
MIX_ENV=prod mix release
HOSTNAME=your-domain.com _build/prod/rel/ambrosia/bin/ambrosia start
```

## Configuration

Environment variables control Ambrosia's behaviour:

| Variable | Default | Description |
|----------|---------|-------------|
| `HOSTNAME` | (required in prod) | Your capsule's domain name |
| `GEMINI_PORT` | 1965 | Port to listen on |
| `ROOT_DIR` | /app/gemini | Directory containing your .gmi files |
| `CERT_FILE` | /certs/cert.pem | Path to TLS certificate |
| `KEY_FILE` | /certs/key.pem | Path to TLS private key |
| `MAX_CONNECTIONS` | 1000 | Maximum concurrent connections |
| `REQUEST_TIMEOUT` | 10000 | Request timeout in milliseconds |
| `RATE_LIMIT_REQUESTS` | 10 | Requests allowed per window |
| `RATE_LIMIT_WINDOW_MS` | 1000 | Rate limit window duration |
| `METRICS_ENABLED` | false | Enable internal Prometheus metrics endpoint |
| `METRICS_PORT` | 9568 | Port for metrics endpoint |

## Content Structure

Organise your Gemini content like this:

```
gemini/
├── index.gmi          # Homepage
├── about.gmi          # About page
├── blog/
│   ├── index.gmi      # Blog index
│   ├── 2024-01-01.gmi # Blog posts
│   └── 2024-01-15.gmi
└── page/
    ├── index.gmi      # Whatever else pleases you
    └── ambrosia.gmi   # Other stuff
```

Ambrosia automatically:
- Serves `index.gmi` or `index.gemini` for directories
- Generates directory listings when no index exists
- Only serves `.gmi` and `.gemini` files (by design)
- The architecture allows MIME type extension

## Monitoring

Enable Prometheus metrics for production monitoring:

```yaml
environment:
  - METRICS_ENABLED=true
  - METRICS_PORT=9568
ports:
  - "127.0.0.1:9568:9568"  # Metrics (localhost only)
```

Available metrics:
- Active connections
- Request duration
- Memory usage
- Process count
- Rate limit hits

## Security

Ambrosia takes security seriously:

- **Path Traversal Protection**: Multiple layers of validation prevent directory escapes
- **Rate Limiting**: Token bucket algorithm prevents abuse
- **TLS Only**: It's Gemini. No plaintext connections
- **Input Validation**: URL length limits and sanitisation
- **Resource Limits**: Connection caps and timeouts
- **Minimal Attack Surface**: Only serves Gemtext files

The codebase includes testing against common attack patterns for the file system

## Testing

Ambrosia includes extensive test coverage:

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Security-specific tests
mix test test/file_server_security_test.exs
```

Tests cover:
- Path traversal attempts
- Rate limiting
- Concurrent connections
- Request parsing
- File serving
- Directory listings
- Edge cases

## Development

### Architecture

Ambrosia uses OTP supervision trees for fault tolerance:

```
Ambrosia.Supervisor
├── Telemetry (Metrics collection)
├── RateLimiter (Token bucket)
├── ConnectionManager (Connection tracking)
├── Ranch Listener (TCP acceptor pool)
└── MetricsExporter (Prometheus endpoint)
```

Each connection runs in its own supervised process. If one crashes, others continue serving.

### Contributing

We welcome contributions! Whether it's:
- Bug fixes
- Performance improvements
- Documentation updates
- Feature suggestions
- Security reports

Please open an issue or PR on [Codeberg](https://codeberg.org/WillC33/ambrosia).

Further testing, fixes, and features are definitely needed before this is ready to use

## Use Cases

Ambrosia works brilliantly for:

- **Personal Capsules**: Your blog, wiki, or digital garden
- **Project Documentation**: Minimalist docs that load instantly
- **Community Spaces**: Shared capsules for groups
- **Archive Mirrors**: Resilient content hosting
- **Educational Resources**: Distraction-free learning materials
- **Creative Writing**: Fiction, poetry, journaling

## Alternatives

The Gemini ecosystem has several excellent servers. This one exists because I love BEAM, not because the other's aren't great:

- **Agate** (Rust): Excellent performance, minimal dependencies
- **Molly Brown** (Go): Feature-rich with CGI support
- **Jetforce** (Python): Great for scripting and extensions
- **GLV-1.12556** (C): Lightweight and portable
- **Gemserv** (Rust): Advanced features like virtual hosting

Choose Ambrosia if you value:
- Erlang's fault tolerance
- Concurrent connection handling
- Simple Docker deployment
- Built-in monitoring

## Thanks

Massive thanks to the Gemini community for creating this wonderful protocol and ecosystem.
This project exists because of your collective work towards a better, lighter internet.

## Philosophy

Ambrosia follows the Gemini philosophy:
- Content over presentation
- Privacy by default
- Simplicity as a feature
- Technical decisions with moral dimensions

We believe the internet can be different. Gemini proves it.

## Licence

AGPL-3.0 - If you improve Ambrosia, share those improvements with the community.

## Etymology

In Greek mythology, ambrosia granted immortality to those who consumed it. This server aims for similar resilience - it should run forever, serving your content reliably across time.

---

*Built with love for the small internet.*

*Find me in Geminispace: gemini://gem.williamcooke.net*

