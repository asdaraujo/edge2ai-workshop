FROM golang:alpine

LABEL maintainer="Dan Chaffelson <chaffelson@gmail.com>"
LABEL site="https://github.com/asdaraujo/edge2ai-workshop/tree/master/setup"

ENV PYTHONUNBUFFERED=0
ENV TZ=${TZ:-"Europe/London"}
ENV ENV=${ENV:-'/setup/terraform/.env'}
ENV STACK=${STACK:-'/setup/terraform/resources/stack.sh'}
ENV TERRAFORMVERSION=${TERRAFORMVERSION:-0.12.20}
ENV PACKERVERSION=${PACKERVERSION:-1.5.1}

RUN apk update && apk upgrade \
    && apk add --no-cache git python3-dev py-pip git linux-headers wget unzip bash openssh jq curl tzdata

RUN cp /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN pip install --upgrade pip \
    && pip install --no-cache jinja2 pyyaml boto3

RUN wget https://releases.hashicorp.com/terraform/${TERRAFORMVERSION}/terraform_${TERRAFORMVERSION}_linux_amd64.zip \
    && unzip terraform_${TERRAFORMVERSION}_linux_amd64.zip \
    && mv terraform /usr/local/bin/terraform \
    && rm terraform_${TERRAFORMVERSION}_linux_amd64.zip

RUN curl -sSLo /tmp/packer.zip https://releases.hashicorp.com/packer/${PACKERVERSION}/packer_${PACKERVERSION}_linux_amd64.zip \
    && unzip /tmp/packer.zip -d /usr/local/bin \
    && rm /tmp/packer.zip

WORKDIR /edge2ai-workshop/setup/terraform

ENTRYPOINT ["/bin/bash"]

