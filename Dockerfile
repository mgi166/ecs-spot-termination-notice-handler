FROM python:alpine

ENV HOME=/srv
WORKDIR /srv

RUN apk add --no-cache curl jq && \
    rm -rf /var/cache/apk/*

RUN pip install awscli

# Copy entrypoint.sh
COPY entrypoint.sh .

# Set permissions on the file.
RUN chmod +x entrypoint.sh

CMD ["/srv/entrypoint.sh"]
