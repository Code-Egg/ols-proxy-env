# OpenLiteSpeed Docker Reverse Proxy

This project runs the official `litespeedtech/openlitespeed` image as a Dockerized OpenLiteSpeed reverse proxy. The primary `.env` domain uses the default `Example` virtual host, and optional additional domains use standalone virtual hosts instead of virtual-host templates.

The configuration includes:

- An OLS `proxy_backend` External App.
- A RewriteRule that proxies all requests to the backend.
- HTTP and HTTPS listeners on ports `80` and `443`.
- OpenLiteSpeed native ACME certificate management.

## Configuration

Copy the example environment file and edit the values:

```sh
cp .env.example .env
```

```dotenv
OLS_IMAGE=litespeedtech/openlitespeed:latest
BACKEND_IP=192.168.0.1
BACKEND_PORT=1234
DOMAIN=www.example.com
ACME_EMAIL=
```

`DOMAIN` is used for the OLS listener mapping and is sent to the backend as the `Host` header.

`BACKEND_IP` is the backend host, not necessarily a numeric IP address. It may be an IP address, DNS hostname, or Docker service/container name such as `backend-service` when both containers share a Docker network. Use the backend container port in that case; for example, `backend-service:8080`, not the host-published port from a `host-port:container-port` mapping.

Set `PROXY_SOCKET=true` to add an OpenLiteSpeed WebSocket proxy block. By default, it reuses `BACKEND_IP` and `BACKEND_PORT`, which is the usual setup when HTTP and WebSocket traffic belong to the same application. Set `PROXY_SOCKET_IP` and `PROXY_SOCKET_PORT` only when the WebSocket service uses a different backend.

## Additional domains

The `.env` configuration always defines the primary single-domain proxy and remains backward compatible. If additional domains are required, add one valid entry per line to `domains.conf`:

```text
DOMAIN, BACKEND_IP, BACKEND_PORT, PROXY_SOCKET
second.example.com, backend-service, 8080, false
```

The primary `.env` domain remains the `Example` virtual host. Each line in `domains.conf` creates an additional virtual host named from the domain, an independent proxy External App, an HTTP/HTTPS listener mapping, and its own ACME-enabled VHost configuration. Do not add `OLS_IMAGE` or `ACME_EMAIL` to `domains.conf`; those settings remain global in `.env`.

`PROXY_SOCKET` must be exactly `true` or `false`. When it is `true`, the WebSocket backend uses the same host and port from that line. The parser rejects missing fields, invalid domains, invalid backend hosts, invalid ports, invalid Boolean values, duplicate domains, and extra comma-separated fields.

The file is mounted read-only into the container, so changing `domains.conf` does not require an image rebuild. Restart the proxy after changes:

```sh
docker compose up -d
```

## Connect another Docker stack

Compose creates a shared bridge network named `ls-net`. Any backend container that should be reached by its Docker service or container name must join this network.

For a backend in another Compose project, add the external network to that project's `docker-compose.yml`:

```yaml
services:
  backend:
    networks:
      - ls-net

networks:
  ls-net:
    external: true
    name: ls-net
```

Then use the backend service name and its internal container port in `.env`:

```dotenv
BACKEND_IP=backend
BACKEND_PORT=8080
```

For a container started with `docker run`, attach it to the shared network:

```sh
docker network connect ls-net <backend-container-name>
```

Use the container's internal listening port, not a host port mapping. For example, a `3000:8080` mapping is reached from OLS as `backend:8080` when both containers use `ls-net`.

## Start and stop

Start the proxy:

```sh
docker compose up -d
```

The first startup builds the local image automatically. It may also pull the selected OpenLiteSpeed base image.

Stop it with:

```sh
docker compose down
```

View status and logs:

```sh
docker compose ps
docker compose logs -f ols-proxy
```

## Automatic HTTPS certificate

OpenLiteSpeed native ACME is enabled at both the server level with `tuning { acme 2 }` and explicitly for the `Example` vhost with `vhssl { acme { enabled 2 } }`. On the first startup, the container runs the image's `/usr/local/lsws/admin/misc/install_acme.sh` once, then OLS creates and renews the certificate when the secure listener and vhost are loaded.

The image also installs `git`, which is required by the native ACME installer to obtain `acme.sh`. When `ACME_EMAIL` is empty, the entrypoint uses the standard installation command without the advanced email option. When `ACME_EMAIL` is not empty, it uses the advanced installation command with `-e "$ACME_EMAIL"`. Use a real email address if you choose the advanced option.

The catch-all proxy rule excludes `/.well-known/acme-challenge/` so OLS native `mod_acme` can handle its stateless challenge response directly. No custom static challenge context is used.

The complete `/usr/local/lsws` directory is stored in the Docker named volume `lsws_data`. This preserves the ACME installation, account data, configuration, logs, and certificates. Certificates are managed by OLS under `/usr/local/lsws/conf/cert/acme/certs`.

The domain must resolve to the Docker host, and inbound TCP port `80` must be reachable by Let's Encrypt. The default `www.example.com` value is only an example and will not issue a certificate unless it points to your server.

## WebAdmin password

WebAdmin port `7080` is disabled by default in `docker-compose.yml`. If you need to access WebAdmin, uncomment `- "7080:7080"` under `ports`, then recreate the container:

```sh
docker compose up -d
```

After finishing WebAdmin changes, comment the port again and recreate the container to stop publishing it.

Do not commit a WebAdmin password to `.env`. Environment files are plain text and can also be exposed through Docker inspection or operational tooling. For a first-time setup, set or reset the password interactively with the official OLS utility:

```sh
docker compose exec ols-proxy /usr/local/lsws/admin/misc/admpass.sh
```

Use the `admin` username when prompted. The WebAdmin credentials are stored in the persisted `lsws_data` volume. Storing a password in `.env` is common for local development, but Docker secrets or an external secret manager are preferable for production.

When `7080` is temporarily enabled, restrict it with a firewall or trusted network. Do not expose WebAdmin publicly unless it is specifically required.

## Configuration reload behavior

`docker-entrypoint.sh` regenerates the primary and additional virtual host and proxy configuration on every container start. The ACME installation itself runs only when `/usr/local/lsws/acme/acme.sh` does not exist. OLS manages subsequent certificate renewal.

Changing `.env` requires restarting the container:

```sh
docker compose down
docker compose up -d
```

Changing `Dockerfile` or `docker-entrypoint.sh` requires rebuilding:

```sh
docker compose up -d --build
```

## Security notes

No Internet-facing service can be guaranteed to be completely secure. This project applies basic defensive measures:

- Validates the backend port, domain, and backend address before writing OLS configuration.
- Keeps the OpenLiteSpeed WebAdmin port `7080` disabled by default; enable it only temporarily and restrict it with a firewall or trusted network.
- Enables Docker's `no-new-privileges` security option.
- Keeps the backend destination controlled by `.env`, rather than accepting it from a request.
- Persists the complete OLS directory, including ACME state and certificates.

For production use, pin `OLS_IMAGE` to a specific version, keep Docker and the image updated, restrict inbound firewall rules, and use a real ACME email address.

If the backend runs in another Docker Compose project, make sure the proxy can reach it through a shared Docker network or a routable host address. If the backend runs on the Docker host, use `host.docker.internal` rather than `127.0.0.1`.
