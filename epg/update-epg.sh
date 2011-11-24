#!/bin/bash
cd /var/lib/vdr/epg/
rm /var/lib/vdr/epg/tnt.zip
rm /var/lib/vdr/epg/tnt.xml
wget http://xmltv.dyndns.org/download/tnt.zip
unzip /var/lib/vdr/epg/tnt.zip
/usr/bin/perl /var/lib/vdr/epg/xmltv2vdr.pl -t 900 -v -x /var/lib/vdr/epg/tnt.xml -c /var/lib/vdr/channels.conf
