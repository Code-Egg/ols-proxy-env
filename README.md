# OpenLiteSpeed Docker Reverse Proxy

This project runs the official `litespeedtech/openlitespeed` image as a Dockerized OpenLiteSpeed reverse proxy. It uses the default `Example` virtual host directly instead of a virtual-host template.

The configuration includes:

- An OLS `proxy_backend` External App.
- A RewriteRule that proxies all requests to the backend.
- HTTP and HTTPS listeners on ports `80` and `443`.
- Automatic Let's Encrypt certificate issuance on first startup.

## Configuration

Copy the example environment file and edit the values:

```sh
cp .env.example .env
```

```dotenv
OLS_IMAGE=litespeedtech/openlitespeed:latest
BACKEND_IP=192.168.0.100
BACKEND_PORT=5678
DOMAIN=www.example.com
ACME_EMAIL=admin@example.com
```

`DOMAIN` is used for the OLS listener mapping and is sent to the backend as the `Host` header.

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

Automatic certificate issuance is enabled by default. On the first startup, the container starts OpenLiteSpeed with the image's fallback certificate, serves the ACME HTTP challenge from the `Example` vhost, and requests a Let's Encrypt certificate for `DOMAIN`.

Certificates are stored under `./acme`, and initialization state is stored under `./state`. A successful issuance is not repeated on subsequent container starts. A failed attempt is also recorded to avoid repeatedly contacting the ACME service; remove the corresponding file under `./state` after fixing DNS, firewall, or port `80` issues and restart the container.

The domain must resolve to the Docker host, and inbound TCP port `80` must be reachable by Let's Encrypt. The default `www.example.com` value is only an example and will not issue a certificate unless it points to your server.

## Configuration reload behavior

`docker-entrypoint.sh` regenerates the Example vhost and proxy configuration on every container start. It uses the official image's server-level baseline configuration so required settings such as `errorLog` are preserved.

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
- Does not expose the OpenLiteSpeed WebAdmin port `7080`.
- Enables Docker's `no-new-privileges` security option.
- Keeps the backend destination controlled by `.env`, rather than accepting it from a request.
- Persists ACME state and avoids repeated certificate issuance attempts.

For production use, pin `OLS_IMAGE` to a specific version, keep Docker and the image updated, restrict inbound firewall rules, and use a real ACME email address.

If the backend runs in another Docker Compose project, make sure the proxy can reach it through a shared Docker network or a routable host address. If the backend runs on the Docker host, use `host.docker.internal` rather than `127.0.0.1`.
