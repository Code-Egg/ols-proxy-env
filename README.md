# OpenLiteSpeed Docker Reverse Proxy

This project runs the official `litespeedtech/openlitespeed` image as a Dockerized OpenLiteSpeed reverse proxy. It uses the default `Example` virtual host directly instead of a virtual-host template.

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
BACKEND_IP=192.168.0.100
BACKEND_PORT=5678
DOMAIN=www.example.com
ACME_EMAIL=admin@example.com
```

`DOMAIN` is used for the OLS listener mapping and is sent to the backend as the `Host` header.

Set `PROXY_SOCKET=true` to add an OpenLiteSpeed WebSocket proxy block using `PROXY_IP` and `PROXY_PORT`. It defaults to `false`, so the WebSocket block is not added unless explicitly enabled.

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

The image also installs `git`, which is required by the native ACME installer to obtain `acme.sh`.

The complete `/usr/local/lsws` directory is stored in the Docker named volume `lsws_data`. This preserves the ACME installation, account data, configuration, logs, and certificates. Certificates are managed by OLS under `/usr/local/lsws/conf/cert/acme/certs`.

The domain must resolve to the Docker host, and inbound TCP port `80` must be reachable by Let's Encrypt. The default `www.example.com` value is only an example and will not issue a certificate unless it points to your server.

## Configuration reload behavior

`docker-entrypoint.sh` regenerates the Example vhost and proxy configuration on every container start. The ACME installation itself runs only when `/usr/local/lsws/acme/acme.sh` does not exist. OLS manages subsequent certificate renewal.

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
- Persists the complete OLS directory, including ACME state and certificates.

For production use, pin `OLS_IMAGE` to a specific version, keep Docker and the image updated, restrict inbound firewall rules, and use a real ACME email address.

If the backend runs in another Docker Compose project, make sure the proxy can reach it through a shared Docker network or a routable host address. If the backend runs on the Docker host, use `host.docker.internal` rather than `127.0.0.1`.
