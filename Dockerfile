FROM crystallang/crystal:0.35.0
ADD . /src
WORKDIR /src
RUN crystal build --release --static -s src/website-entrypoint.cr

FROM debian:stretch-slim
RUN apt-get update \
	&& apt-get --no-install-recommends -y install ca-certificates \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/*

RUN adduser --disabled-password --gecos "" docker
USER docker
COPY --from=0 /src/website-entrypoint /
COPY --from=0 /src/src/website/public/ /public/
