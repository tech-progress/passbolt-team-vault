FROM passbolt/passbolt:5.16.0-1-ce-non-root@sha256:1f6aba5b18199809de9aaec17ba1525b88ac75be9390c5fc343b88a9b18f525d AS runtime

USER root
RUN mkdir -p /var/lib/passbolt/keys/gpg /var/lib/passbolt/keys/jwt \
    && rm -rf /etc/passbolt/gpg /etc/passbolt/jwt \
    && ln -s /var/lib/passbolt/keys/gpg /etc/passbolt/gpg \
    && ln -s /var/lib/passbolt/keys/jwt /etc/passbolt/jwt \
    && chown -R www-data:www-data /var/lib/passbolt \
    && grep -Fq 'chmod 750 "$passbolt_config/jwt"' /passbolt/entrypoint-rootless.sh \
    && sed -i 's/chmod 750 "$passbolt_config\/jwt"/chmod 550 "$passbolt_config\/jwt"/' /passbolt/entrypoint-rootless.sh \
    && sed -i 's,/var/run/supervisord.pid,/tmp/supervisord.pid,' /etc/supervisor/supervisord.conf \
    && sed -i '/include \/etc\/nginx\/snippets\/passbolt-ssl.conf;/d' /etc/nginx/sites-available/nginx-passbolt.conf \
    && sed -i '/fastcgi_param[[:space:]]*REQUEST_SCHEME[[:space:]]/d; /fastcgi_param[[:space:]]*HTTPS[[:space:]]/d; /fastcgi_param[[:space:]]*HTTP_HOST[[:space:]]/d' /etc/nginx/fastcgi_params \
    && sed -i '/fastcgi_param            SERVER_NAME/a\    fastcgi_param HTTPS $template_https if_not_empty;\n    fastcgi_param REQUEST_SCHEME $template_scheme;\n    fastcgi_param HTTP_HOST $template_host;' /etc/nginx/sites-available/nginx-passbolt.conf
COPY scripts/entrypoint.sh scripts/healthcheck.sh scripts/state-identity.sh scripts/cake.sh scripts/validate-runtime.php /opt/template/
COPY LICENSE /opt/template/LICENSE
RUN chmod 755 /opt/template/*.sh && chmod 644 /opt/template/*.php
USER www-data
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=10s --start-period=180s --retries=4 CMD ["/opt/template/healthcheck.sh"]
ENTRYPOINT ["/opt/template/entrypoint.sh"]
CMD []

FROM runtime AS smtp-fixture
COPY scripts/smtp-fixture.php /opt/template/smtp-fixture.php
COPY LICENSE /opt/template/LICENSE
ENTRYPOINT ["php", "/opt/template/smtp-fixture.php"]
HEALTHCHECK NONE

FROM runtime AS production
