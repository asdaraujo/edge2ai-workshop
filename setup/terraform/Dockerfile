FROM golang:alpine

LABEL maintainer="Andre Araujo <araujo@cloudera.com>"
LABEL site="https://github.com/asdaraujo/edge2ai-workshop/tree/master/setup"

ENV INSIDE_DOCKER_CONTAINER=1
ENV PYTHONUNBUFFERED=0
ENV TERRAFORM12VERSION=${TERRAFORM12VERSION:-0.12.30}
ENV TERRAFORM12=/usr/local/bin/terraform12
ENV TERRAFORM14VERSION=${TERRAFORM14VERSION:-0.14.8}
ENV TERRAFORM14=/usr/local/bin/terraform14
ENV PACKERVERSION=${PACKERVERSION:-1.5.1}
ENV GLIBC_VER=2.31-r0

RUN apk update && apk upgrade \
    && apk add --no-cache git python3-dev py-pip git linux-headers wget unzip bash openssh jq curl tzdata

RUN cp /usr/share/zoneinfo/Europe/London /etc/localtime && echo Europe/London > /etc/timezone

RUN pip install --upgrade pip \
    && pip install --no-cache jinja2 pyyaml boto3

RUN wget https://releases.hashicorp.com/terraform/${TERRAFORM12VERSION}/terraform_${TERRAFORM12VERSION}_linux_amd64.zip \
    && unzip terraform_${TERRAFORM12VERSION}_linux_amd64.zip \
    && mv terraform ${TERRAFORM12} \
    && rm terraform_${TERRAFORM12VERSION}_linux_amd64.zip \
    && wget https://releases.hashicorp.com/terraform/${TERRAFORM14VERSION}/terraform_${TERRAFORM14VERSION}_linux_amd64.zip \
    && unzip terraform_${TERRAFORM14VERSION}_linux_amd64.zip \
    && mv terraform ${TERRAFORM14} \
    && rm terraform_${TERRAFORM14VERSION}_linux_amd64.zip \
    && ln -s ${TERRAFORM14} /usr/local/bin/terraform

# AWSCLI v2
RUN apk --no-cache add \
        binutils \
        curl \
    && curl -sL https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub -o /etc/apk/keys/sgerrand.rsa.pub \
    && curl -sLO https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VER}/glibc-${GLIBC_VER}.apk \
    && curl -sLO https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VER}/glibc-bin-${GLIBC_VER}.apk \
    && curl -sLO https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VER}/glibc-i18n-${GLIBC_VER}.apk \
    && apk add --no-cache \
        glibc-${GLIBC_VER}.apk \
        glibc-bin-${GLIBC_VER}.apk \
        glibc-i18n-${GLIBC_VER}.apk \
    && /usr/glibc-compat/bin/localedef -i en_US -f UTF-8 en_US.UTF-8 \
    && curl -sL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip \
    && unzip awscliv2.zip \
    && aws/install \
    && rm -rf \
        awscliv2.zip \
        aws \
        /usr/local/aws-cli/v2/current/dist/aws_completer \
        /usr/local/aws-cli/v2/current/dist/awscli/data/ac.index \
        /usr/local/aws-cli/v2/current/dist/awscli/examples \
        glibc-*.apk \
    && apk --no-cache del \
        binutils \
    && rm -rf /var/cache/apk/*

RUN curl -sSLo /tmp/packer.zip https://releases.hashicorp.com/packer/${PACKERVERSION}/packer_${PACKERVERSION}_linux_amd64.zip \
    && unzip /tmp/packer.zip -d /usr/local/bin \
    && rm /tmp/packer.zip

RUN which python || ln -s $(which python3) /usr/bin/python

WORKDIR /edge2ai-workshop/setup/terraform

ENTRYPOINT ["/bin/bash"]

