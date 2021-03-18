FROM golang:alpine

LABEL maintainer="Andre Araujo <araujo@cloudera.com>"
LABEL site="https://github.com/asdaraujo/edge2ai-workshop/tree/master/setup"

ENV PYTHONUNBUFFERED=0
ENV TZ=${TZ:-"Europe/London"}
ENV ENV=${ENV:-'/setup/terraform/.env'}
ENV STACK=${STACK:-'/setup/terraform/resources/stack.sh'}
ENV TERRAFORM12VERSION=${TERRAFORM12VERSION:-0.12.30}
ENV TERRAFORM12=/usr/local/bin/terraform12
ENV TERRAFORM14VERSION=${TERRAFORM14VERSION:-0.14.8}
ENV TERRAFORM14=/usr/local/bin/terraform14
ENV PACKERVERSION=${PACKERVERSION:-1.5.1}

RUN apk update && apk upgrade \
    && apk add --no-cache git python3-dev py-pip git linux-headers wget unzip bash openssh jq curl tzdata

RUN cp /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN pip install --upgrade pip \
    && pip install --no-cache jinja2 pyyaml boto3 awscli

RUN wget https://releases.hashicorp.com/terraform/${TERRAFORM12VERSION}/terraform_${TERRAFORM12VERSION}_linux_amd64.zip \
    && unzip terraform_${TERRAFORM12VERSION}_linux_amd64.zip \
    && mv terraform ${TERRAFORM12} \
    && rm terraform_${TERRAFORM12VERSION}_linux_amd64.zip \
    && wget https://releases.hashicorp.com/terraform/${TERRAFORM14VERSION}/terraform_${TERRAFORM14VERSION}_linux_amd64.zip \
    && unzip terraform_${TERRAFORM14VERSION}_linux_amd64.zip \
    && mv terraform ${TERRAFORM14} \
    && rm terraform_${TERRAFORM14VERSION}_linux_amd64.zip \
    && ln -s ${TERRAFORM14} /usr/local/bin/terraform

RUN curl -sSLo /tmp/packer.zip https://releases.hashicorp.com/packer/${PACKERVERSION}/packer_${PACKERVERSION}_linux_amd64.zip \
    && unzip /tmp/packer.zip -d /usr/local/bin \
    && rm /tmp/packer.zip

RUN which python || ln -s $(which python3) /usr/bin/python

WORKDIR /edge2ai-workshop/setup/terraform

ENTRYPOINT ["/bin/bash"]

