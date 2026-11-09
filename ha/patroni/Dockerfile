FROM postgres:17-bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-venv \
 && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/patroni \
 && /opt/patroni/bin/pip install --no-cache-dir "patroni[etcd3]" psycopg2-binary

ENV PATH="/opt/patroni/bin:${PATH}"

USER postgres
ENTRYPOINT ["/opt/patroni/bin/patroni", "/etc/patroni.yml"]
