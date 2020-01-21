FROM python:3.6-alpine

LABEL maintainer="Dan Chaffelson <chaffelson@gmail.com>"
LABEL site="https://github.com/asdaraujo/edge2ai-workshop/tree/master/setup"

ENV PYTHONUNBUFFERED=0
ENV TZ=${TZ:-"Europe/London"}
ENV ENV=${ENV:-'/setup/terraform/.env'}
ENV STACK=${STACK:-'/setup/terraform/resources/stack.sh'}
ENV TERRAFORMVERSION=${TERRAFORMVERSION:-0.12.19}

RUN apk update && apk upgrade \
    && apk add --no-cache git python3-dev linux-headers wget unzip bash openssh jq curl tzdata

RUN pip install --upgrade pip \
    && cp /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN wget https://releases.hashicorp.com/terraform/${TERRAFORMVERSION}/terraform_${TERRAFORMVERSION}_linux_amd64.zip \
    && unzip terraform_${TERRAFORMVERSION}_linux_amd64.zip \
    && mv terraform /usr/local/bin/terraform \
    && rm terraform_${TERRAFORMVERSION}_linux_amd64.zip

RUN git clone -b master --depth 1 https://github.com/asdaraujo/edge2ai-workshop.git /edge2ai-workshop

RUN pip install --no-cache jinja2 pyyaml \
    && cp /edge2ai-workshop/setup/terraform/.env.template /edge2ai-workshop/setup/terraform/.env \
    && cp /edge2ai-workshop/setup/terraform/resources/stack.template.sh /edge2ai-workshop/setup/terraform/resources/stack.sh


WORKDIR /edge2ai-workshop/setup/terraform

ENTRYPOINT ["/bin/bash"]

# export ENV=/Users/dchaffelson/PycharmProjects/aaedge2ai-workshop/setup/terraform/.env
# export STACK=/Users/dchaffelson/PycharmProjects/aaedge2ai-workshop/setup/terraform/resources/stack.sh
# docker run -ti -v ${ENV}:/edge2ai-workshop/setup/terraform/.env:ro -v ${STACK}:/edge2ai-workshop/setup/terraform/resources/stack.sh cldrbootcamp