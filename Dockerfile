FROM shimaore/debian:2.0.2
MAINTAINER Stéphane Alnet <stephane@shimaore.net>

# Install Node.js using `n`.
RUN git clone https://github.com/tj/n.git
WORKDIR n
RUN make install
WORKDIR ..
RUN n io 2.5.0
ENV NODE_ENV production

RUN apt-get update && apt-get -y --no-install-recommends install \
  supervisor

COPY . /opt/willing-toothbrush
WORKDIR /opt/willing-toothbrush
RUN mkdir -p log
RUN npm install

CMD ["/usr/bin/supervisord","-n"]
