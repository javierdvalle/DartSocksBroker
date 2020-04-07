# DartSocksBroker

Pool of proxies under NAT schema: One public broker - multiple workers under NAT:

1. Broker gets up and exposes a public IP.
2. Workers register with the broker. Workers can be under a NAT.
3. Configure a client browser to use a typical SOCKS4 proxy, with the broker IP.
4. Client browser visits a website. The connection is forwarded to the broker, which forwards the connection to a worker, which forwards the connection to the end host. 

Client browser  <-- SOCKS4 -->  Proxy Broker  <---->  Proxy Worker (under NAT)  <---->  End Host
