ARG OLS_IMAGE=litespeedtech/openlitespeed:latest
FROM ${OLS_IMAGE}

COPY docker-entrypoint.sh /usr/local/bin/ols-proxy-entrypoint.sh
RUN chmod +x /usr/local/bin/ols-proxy-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/ols-proxy-entrypoint.sh"]
