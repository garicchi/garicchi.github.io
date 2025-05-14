FROM debian:trixie-slim


ENV TZ "Asia/Tokyo"
RUN cp /usr/share/zoneinfo/${TZ} /etc/localtime

RUN apt-get update && apt-get upgrade -y curl

RUN curl -L -o hugo.deb https://github.com/gohugoio/hugo/releases/download/v0.147.3/hugo_0.147.3_linux-amd64.deb \
    && dpkg -i hugo.deb \
    && rm -f hugo.deb
