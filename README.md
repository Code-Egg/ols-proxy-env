# OpenLiteSpeed Docker Reverse Proxy

This project runs the official `litespeedtech/openlitespeed` image as a Dockerized OpenLiteSpeed reverse proxy. At container startup, OpenLiteSpeed reads the backend address and public domain from `.env`, creates a virtual-host-template member for that domain, and proxies all HTTP requests to the backend.

## Configuration

Copy the example environment file and edit the values:

```sh
cp .env.example .env
```

```dotenv
OLS_IMAGE=litespeedtech/openlitespeed:latest
BACKEND_IP=192.168.1.100
BACKEND_PORT=5678
DOMAIN=www.example.com
```

`DOMAIN` is sent to the backend as the `Host` header. This is useful for applications such as n8n that need to know their public hostname.

## Start and stop

Start the proxy on the standard HTTP and HTTPS ports:

```sh
docker compose up -d --build
```

The Compose file explicitly builds the local `ols-proxy:local` image. It does not pull that image from Docker Hub.

The proxy listens on:

- `80/tcp` for HTTP
- `443/tcp` for HTTPS

Stop it with:

```sh
docker compose down
```

View status and logs:

```sh
docker compose ps
docker compose logs -f ols-proxy
```

## Configuration reload behavior

`docker-entrypoint.sh` generates the OLS listener configuration, virtual-host-template member, and domain-specific vhost configuration before starting OpenLiteSpeed. Therefore, the configuration is regenerated on every container start or restart. Changing `.env` requires recreating or restarting the container:

```sh
docker compose up -d --build
```

An OpenLiteSpeed graceful restart performed inside an already-running container does not rerun the entrypoint script.

## Security notes

No Internet-facing service can be guaranteed to be completely secure. This project applies basic defensive measures:

- Validates the backend port, domain, and backend address before writing OLS configuration.
- Does not expose the OpenLiteSpeed WebAdmin port `7080`.
- Enables Docker's `no-new-privileges` security option.
- Keeps the backend destination controlled by `.env`, rather than accepting it from a request.
- Uses the official OpenLiteSpeed image as the base image.

For production use, pin `OLS_IMAGE` to a specific version, keep Docker and the image updated, restrict inbound firewall rules, and configure a valid TLS certificate for HTTPS. Until then, HTTPS uses the image's default WebAdmin certificate and browsers will show a certificate warning.

If the backend runs in another Docker Compose project, make sure the proxy can reach it through a shared Docker network or a routable host address.
