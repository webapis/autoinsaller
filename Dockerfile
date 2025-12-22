FROM semaphoreui/semaphore:latest
USER root
RUN apk add --no-cache build-base libffi-dev openssl-dev python3-dev py3-pip krb5-dev
RUN pip3 install --break-system-packages pywinrm[credssp]
USER 1001
RUN ansible-galaxy collection install ansible.windows
RUN ansible-galaxy collection install community.windows