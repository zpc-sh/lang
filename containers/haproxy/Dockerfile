FROM haproxy:2.8-alpine
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg
CMD ["haproxy","-f","/usr/local/etc/haproxy/haproxy.cfg","-db"]
