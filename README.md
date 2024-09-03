# dnsperf
DNS Server Performance Tester


Bash script, written for use on a mac/terminal. Can probably work on linux.

Prerequisites:
gnuplot
parallel

brew install parallel gnuplot


usage: ./dnsperf.sh -s servers.txt -d domains.txt

servers.txt should contain a list of DNS servers that you want evaluated for performance. (eg 8.8.8.8) - Each entry on a new line

domains.txt should contain the services that you consume over the dns (eg amazon.com)  - Each entry on a new line

Primary use case is using a DNS/Proxy/VPN provider and they supply a global list of IPs and you need the best performing ones for your location, or to troubleshoot an existing configuration. This initial list uses smartdnsproxy IPs since I'm a customer and check performance periodically.

You'll get a nice graph output showing them all.


This is a work in progress, so caveat emptor.



