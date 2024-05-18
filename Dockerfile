# builder image

# start of ems-base-image
FROM node:18.17.1-alpine3.17 AS builder

ARG SKY_INTRANET_CA_URL=https://sky-it-scc.s3-eu-west-1.amazonaws.com/SKY-Intranet-CA1586248834.cer
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
ENV NODE_APP_PATH=/app

COPY concourse/certs /tmp/certs

RUN apk add --no-cache \
  ca-certificates && \
  apk add --no-cache --virtual temp \
  curl \
  openssl && \
  curl -sSfL ${SKY_INTRANET_CA_URL} -o /tmp/SKY-Intranet-CA.der && \
  openssl x509 -inform DER -outform PEM -in /tmp/SKY-Intranet-CA.der -out /usr/local/share/ca-certificates/SKY-Intranet-CA.crt && \
  cp /tmp/certs/* /usr/local/share/ca-certificates/ && \
  update-ca-certificates && \
  npm cache clean --force && \
  apk del temp && \
  rm -fr /tmp/SKY-Intranet-CA.der /tmp/certs /usr/local/share/ca-certificates/*.crt && \
  mkdir ${NODE_APP_PATH} && chown node:node ${NODE_APP_PATH} && chmod 775 ${NODE_APP_PATH} && \
  adduser -D -u 12345 -h /home/nodeapp -s /bin/sh nodeapp && \
  addgroup -g 12321 nodedevs && addgroup node nodedevs && addgroup nodeapp nodedevs

USER node

WORKDIR ${NODE_APP_PATH}

# smoke test
RUN npm --version && node --version
# end of ems-base-image

COPY package*.json ./
COPY .npmrc ./

RUN npm clean-install --omit=optional

COPY . .

RUN npm run build

# Aggiungi il comando per eseguire il tool di testing e controllare i parametri
RUN npm run test-tool

# Copia lo script Node.js nel container
COPY index.js /app/index.js

# Esegui il tool di testing come parte della build
RUN node index.js --file $MANIFEST_DASH

# production image

# start of ems-base-image
FROM node:18.17.1-alpine3.17

ARG SKY_INTRANET_CA_URL=https://sky-it-scc.s3-eu-west-1.amazonaws.com/SKY-Intranet-CA1586248834.cer
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
ENV NODE_APP_PATH=/app

COPY concourse/certs /tmp/certs

RUN apk add --no-cache \
  ca-certificates && \
  apk add --no-cache --virtual temp \
  curl \
  openssl && \
  curl -sSfL ${SKY_INTRANET_CA_URL} -o /tmp/SKY-Intranet-CA.der && \
  openssl x509 -inform DER -outform PEM -in /tmp/SKY-Intranet-CA.der -out /usr/local/share/ca-certificates/SKY-Intranet-CA.crt && \
  cp /tmp/certs/* /usr/local/share/ca-certificates/ && \
  update-ca-certificates && \
  npm cache clean --force && \
  apk del temp && \
  rm -fr /tmp/SKY-Intranet-CA.der /tmp/certs /usr/local/share/ca-certificates/*.crt && \
  mkdir ${NODE_APP_PATH} && chown node:node ${NODE_APP_PATH} && chmod 775 ${NODE_APP_PATH} && \
  adduser -D -u 12345 -h /home/nodeapp -s /bin/sh nodeapp && \
  addgroup -g 12321 nodedevs && addgroup node nodedevs && addgroup nodeapp nodedevs

USER node

WORKDIR ${NODE_APP_PATH}

# smoke test
RUN npm --version && node --version
# end of ems-base image

LABEL name="crostino"
LABEL description="CROSTINO"
LABEL maintainer="brunellie"

ENV NODE_ENV=production

COPY --chown=node:node package*.json ./
COPY --chown=node:node .npmrc ./

RUN npm clean-install --omit=optional && \
  npm cache clean --force


# Copia lo script Node.js nel container finale
COPY --from=builder /app/index.js /app/index.js

COPY --chown=node:node --from=builder ${NODE_APP_PATH}/dist ./dist/

EXPOSE 3001

USER nodeapp

CMD [ "npm", "start" ]


