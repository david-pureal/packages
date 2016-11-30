#!/bin/sh
##############################################################################
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# Copyright (C) 2016 Eric Luehrsen
#
##############################################################################
#
# This builds the basic UCI components currently supported for Unbound. It is
# intentionally NOT comprehensive and bundles a lot of options. The UCI is to
# be a simpler presentation of the total Unbound conf set.
#
##############################################################################

UNBOUND_B_CONTROL=0
UNBOUND_B_DNSMASQ=0
UNBOUND_B_DNSSEC=0
UNBOUND_B_GATE_NAME=0
UNBOUND_B_LOCL_BLCK=0
UNBOUND_B_LOCL_NAME=0
UNBOUND_B_LOCL_SERV=1
UNBOUND_B_MAN_CONF=0
UNBOUND_B_NTP_BOOT=1
UNBOUND_B_PRIV_BLCK=1
UNBOUND_B_QUERY_MIN=0

UNBOUND_D_RESOURCE=small
UNBOUND_D_RECURSION=passive

UNBOUND_TXT_FWD_ZONE=""
UNBOUND_TTL_MIN=120

UNBOUND_N_EDNS_SIZE=1280
UNBOUND_N_FWD_PORTS=""
UNBOUND_N_RX_PORT=53
UNBOUND_N_ROOT_AGE=28

##############################################################################

UNBOUND_ANCHOR=/usr/bin/unbound-anchor
UNBOUND_CONTROL=/usr/bin/unbound-control

UNBOUND_LIBDIR=/usr/lib/unbound

UNBOUND_PIDFILE=/var/run/unbound.pid

UNBOUND_VARDIR=/var/lib/unbound
UNBOUND_CONFFILE=$UNBOUND_VARDIR/unbound.conf
UNBOUND_KEYFILE=$UNBOUND_VARDIR/root.key
UNBOUND_HINTFILE=$UNBOUND_VARDIR/root.hints
UNBOUND_TIMEFILE=$UNBOUND_VARDIR/unbound.time
UNBOUND_CHECKFILE=$UNBOUND_VARDIR/unbound.check

##############################################################################

. /lib/functions.sh
. /lib/functions/network.sh

. $UNBOUND_LIBDIR/dnsmasq.sh
. $UNBOUND_LIBDIR/iptools.sh
. $UNBOUND_LIBDIR/rootzone.sh

##############################################################################

create_access_control() {
  local cfg="$1"
  local subnets subnets4 subnets6
  local validip4 validip6

  network_get_subnets  subnets4 "$cfg"
  network_get_subnets6 subnets6 "$cfg"
  subnets="$subnets4 $subnets6"


  if [ -n "$subnets" ] ; then
    for subnet in $subnets ; do
      validip4=$( valid_subnet4 $subnet )
      validip6=$( valid_subnet6 $subnet )


      if [ "$validip4" = "ok" -o "$validip6" = "ok" ] ; then
        # For each "network" UCI add "access-control:" white list for queries
        echo "  access-control: $subnet allow" >> $UNBOUND_CONFFILE
      fi
    done
  fi
}

##############################################################################

create_domain_insecure() {
  echo "  domain-insecure: \"$1\"" >> $UNBOUND_CONFFILE
}

##############################################################################

unbound_mkdir() {
  mkdir -p $UNBOUND_VARDIR


  if [ -f /etc/unbound/root.hints ] ; then
    # Your own local copy of root.hints
    cp -p /etc/unbound/root.hints $UNBOUND_HINTFILE

  elif [ -f /usr/share/dns/root.hints ] ; then
    # Debian-like package dns-root-data
    cp -p /usr/share/dns/root.hints $UNBOUND_HINTFILE

  else
    logger -t unbound -s "iterator will use built-in root hints"
  fi


  if [ -f /etc/unbound/root.key ] ; then
    # Your own local copy of a root.key
    cp -p /etc/unbound/root.key $UNBOUND_KEYFILE

  elif [ -f /usr/share/dns/root.key ] ; then
    # Debian-like package dns-root-data
    cp -p /usr/share/dns/root.key $UNBOUND_KEYFILE

  elif [ -x "$UNBOUND_ANCHOR" ] ; then
    $UNBOUND_ANCHOR -a $UNBOUND_KEYFILE

  else
    logger -t unbound -s "validator will use built-in trust anchor"
  fi
}

##############################################################################

unbound_conf() {
  local cfg=$1
  local rt_mem rt_conn

  {
    # Make fresh conf file
    echo "# $UNBOUND_CONFFILE generated by UCI $( date )"
    echo
  } > $UNBOUND_CONFFILE


  if [ "$UNBOUND_B_CONTROL" -gt 0 ] ; then
    {
      # Enable remote control tool, but only at local host for security
      echo "remote-control:"
      echo "  control-enable: yes"
      echo "  control-use-cert: no"
      echo "  control-interface: 127.0.0.1"
      echo "  control-interface: ::1"
      echo
    } >> $UNBOUND_CONFFILE

  else
    {
      # "control:" clause is seperate before "server:" so we can append
      # dnsmasq "server:" parts and "forward:" cluases towards the end.
      echo "remote-control:"
      echo "  control-enable: no"
      echo
    } >> $UNBOUND_CONFFILE
  fi


  {
    # No threading
    echo "server:"
    echo "  username: unbound"
    echo "  num-threads: 1"
    echo "  msg-cache-slabs: 1"
    echo "  rrset-cache-slabs: 1"
    echo "  infra-cache-slabs: 1"
    echo "  key-cache-slabs: 1"
    echo
  } >> $UNBOUND_CONFFILE


  {
    # Logging
    echo "  verbosity: 1"
    echo "  statistics-interval: 0"
    echo "  statistics-cumulative: no"
    echo "  extended-statistics: no"
    echo
  } >> $UNBOUND_CONFFILE


  {
    # Interfaces (access contol "option local_service")
    echo "  interface: 0.0.0.0"
    echo "  interface: ::0"
    echo "  outgoing-interface: 0.0.0.0"
    echo "  outgoing-interface: ::0"
    echo
  } >> $UNBOUND_CONFFILE


  {
    # protocol level tuning
    echo "  edns-buffer-size: $UNBOUND_N_EDNS_SIZE"
    echo "  msg-buffer-size: 8192"
    echo "  port: $UNBOUND_N_RX_PORT"
    echo "  outgoing-port-permit: 10240-65535"
    echo
  } >> $UNBOUND_CONFFILE


  {
    # Other harding and options for an embedded router
    echo "  harden-short-bufsize: yes"
    echo "  harden-large-queries: yes"
    echo "  harden-glue: yes"
    echo "  harden-below-nxdomain: no"
    echo "  harden-referral-path: no"
    echo "  use-caps-for-id: no"
    echo
  } >> $UNBOUND_CONFFILE


  {
    # Default Files
    echo "  use-syslog: yes"
    echo "  chroot: \"$UNBOUND_VARDIR\""
    echo "  directory: \"$UNBOUND_VARDIR\""
    echo "  pidfile: \"$UNBOUND_PIDFILE\""
  } >> $UNBOUND_CONFFILE


  if [ -f "$UNBOUND_HINTFILE" ] ; then
    # Optional hints if found
    echo "  root-hints: \"$UNBOUND_HINTFILE\"" >> $UNBOUND_CONFFILE
  fi


  if [ "$UNBOUND_B_DNSSEC" -gt 0 -a -f "$UNBOUND_KEYFILE" ] ; then
    {
      echo "  auto-trust-anchor-file: \"$UNBOUND_KEYFILE\""
      echo
    } >> $UNBOUND_CONFFILE

  else
    echo >> $UNBOUND_CONFFILE
  fi


  case "$UNBOUND_D_RESOURCE" in
    # Tiny - Unbound's recommended cheap hardware config
    tiny)   rt_mem=1  ; rt_conn=1 ;;
    # Small - Half RRCACHE and open ports
    small)  rt_mem=8  ; rt_conn=5 ;;
    # Medium - Nearly default but with some added balancintg
    medium) rt_mem=16 ; rt_conn=10 ;;
    # Large - Double medium
    large)  rt_mem=32 ; rt_conn=10 ;;
    # Whatever unbound does
    *) rt_mem=0 ; rt_conn=0 ;;
  esac


  if [ "$rt_mem" -gt 0 ] ; then
    {
      # Set memory sizing parameters
      echo "  outgoing-range: $(($rt_conn*64))"
      echo "  num-queries-per-thread: $(($rt_conn*32))"
      echo "  outgoing-num-tcp: $(($rt_conn))"
      echo "  incoming-num-tcp: $(($rt_conn))"
      echo "  rrset-cache-size: $(($rt_mem*256))k"
      echo "  msg-cache-size: $(($rt_mem*128))k"
      echo "  key-cache-size: $(($rt_mem*128))k"
      echo "  neg-cache-size: $(($rt_mem*64))k"
      echo "  infra-cache-numhosts: $(($rt_mem*256))"
      echo
    } >> $UNBOUND_CONFFILE

  else
    logger -t unbound -s "default memory resource consumption"
  fi


  if [ "$UNBOUND_B_DNSSEC" -gt 0 ] ; then
    if [ ! -f "$UNBOUND_TIMEFILE" -a "$UNBOUND_B_NTP_BOOT" -gt 0 ] ; then
      # DNSSEC chicken and egg with getting NTP time
      echo "  val-override-date: -1" >> $UNBOUND_CONFFILE
    fi


    {
      # Validation of DNSSEC
      echo "  module-config: \"validator iterator\""
      echo "  harden-dnssec-stripped: yes"
      echo "  val-clean-additional: yes"
      echo "  ignore-cd-flag: yes"
      echo
    } >> $UNBOUND_CONFFILE

  else
    {
      # Just iteration without DNSSEC
      echo "  module-config: \"iterator\""
      echo
    } >> $UNBOUND_CONFFILE
  fi


  if [ "$UNBOUND_B_QUERY_MIN" -gt 0 ] ; then
    # Minor improvement on query privacy
    echo "  qname-minimisation: yes" >> $UNBOUND_CONFFILE

  else
    echo "  qname-minimisation: no" >> $UNBOUND_CONFFILE
  fi


  case "$UNBOUND_D_RECURSION" in
    passive)
      {
        echo "  prefetch: no"
        echo "  prefetch-key: no"
        echo "  target-fetch-policy: \"0 0 0 0 0\""
        echo
      } >> $UNBOUND_CONFFILE
      ;;

    aggressive)
      {
        echo "  prefetch: yes"
        echo "  prefetch-key: yes"
        echo "  target-fetch-policy: \"3 2 1 0 0\""
        echo
      } >> $UNBOUND_CONFFILE
      ;;

    *)
      logger -t unbound -s "default recursion configuration"
      ;;
  esac


  {
    # Reload records more than 10 hours old
    # DNSSEC 5 minute bogus cool down before retry
    # Adaptive infrastructure info kept for 15 minutes
    echo "  cache-min-ttl: $UNBOUND_TTL_MIN"
    echo "  cache-max-ttl: 36000"
    echo "  val-bogus-ttl: 300"
    echo "  infra-host-ttl: 900"
    echo
  } >> $UNBOUND_CONFFILE


  if [ "$UNBOUND_B_PRIV_BLCK" -gt 0 ] ; then
    {
      # Remove DNS reponses from upstream with private IP
      echo "  private-address: 10.0.0.0/8"
      echo "  private-address: 169.254.0.0/16"
      echo "  private-address: 172.16.0.0/12"
      echo "  private-address: 192.168.0.0/16"
      echo "  private-address: fc00::/8"
      echo "  private-address: fd00::/8"
      echo "  private-address: fe80::/10"
    } >> $UNBOUND_CONFFILE
  fi


  if [ "$UNBOUND_B_LOCL_BLCK" -gt 0 ] ; then
    {
      # Remove DNS reponses from upstream with loopback IP
      # Black hole DNS method for ad blocking, so consider...
      echo "  private-address: 127.0.0.0/8"
      echo "  private-address: ::1/128"
      echo
    } >> $UNBOUND_CONFFILE

  else
    echo >> $UNBOUND_CONFFILE
  fi


  # Domain Exceptions
  config_list_foreach "$cfg" "domain_insecure" create_domain_insecure
  echo >> $UNBOUND_CONFFILE


  ####################
  # UCI @ network    #
  ####################


  if [ "$UNBOUND_B_LOCL_SERV" -gt 0 ] ; then
    # Only respond to queries from which this device has an interface.
    # Prevent DNS amplification attacks by not responding to the universe.
    config_load network
    config_foreach create_access_control interface

    {
      echo "  access-control: 127.0.0.0/8 allow"
      echo "  access-control: ::1/128 allow"
      echo "  access-control: fe80::/10 allow"
      echo
    } >> $UNBOUND_CONFFILE

  else
    {
      echo "  access-control: 0.0.0.0/0 allow"
      echo "  access-control: ::0/0 allow"
      echo
    } >> $UNBOUND_CONFFILE
  fi
}

##############################################################################

unbound_uci() {
  local cfg=$1
  local dnsmasqpath

  ####################
  # UCI @ unbound    #
  ####################

  config_get_bool UNBOUND_B_GATE_NAME "$cfg" dnsmsaq_gate_name 0
  config_get_bool UNBOUND_B_DNSMASQ   "$cfg" dnsmasq_link_dns 0
  config_get_bool UNBOUND_B_LOCL_NAME "$cfg" dnsmasq_only_local 0
  config_get_bool UNBOUND_B_LOCL_SERV "$cfg" localservice 1
  config_get_bool UNBOUND_B_MAN_CONF  "$cfg" manual_conf 0
  config_get_bool UNBOUND_B_QUERY_MIN "$cfg" query_minimize 0
  config_get_bool UNBOUND_B_PRIV_BLCK "$cfg" rebind_protection 1
  config_get_bool UNBOUND_B_LOCL_BLCK "$cfg" rebind_localhost 0
  config_get_bool UNBOUND_B_CONTROL   "$cfg" unbound_control 0
  config_get_bool UNBOUND_B_DNSSEC    "$cfg" validator  0
  config_get_bool UNBOUND_B_NTP_BOOT  "$cfg" validator_ntp 1

  config_get UNBOUND_N_EDNS_SIZE "$cfg" edns_size 1280
  config_get UNBOUND_N_RX_PORT   "$cfg" listen_port 53
  config_get UNBOUND_D_RECURSION "$cfg" recursion passive
  config_get UNBOUND_D_RESOURCE  "$cfg" resource small
  config_get UNBOUND_N_ROOT_AGE  "$cfg" root_age 7
  config_get UNBOUND_TTL_MIN     "$cfg" ttl_min 120


  if [ "$UNBOUND_B_DNSMASQ" -gt 0 ] ; then
    dnsmasqpath=$( which dnsmasq )


    if [ ! -x "$dnsmasqpath" ] ; then
      logger -t unbound -s "cannot forward to dnsmasq"
      UNBOUND_B_DNSMASQ=0
    fi
  fi


  if [ "$UNBOUND_N_EDNS_SIZE" -lt 512 \
    -o 4096 -lt "$UNBOUND_N_EDNS_SIZE" ] ; then
    # exceeds range, back to default
    UNBOUND_N_EDNS_SIZE=1280
  fi


  if [ "$UNBOUND_N_RX_PORT" -lt 1024 \
    -o 10240 -lt "$UNBOUND_N_RX_PORT" ] ; then
    # special port or in 5 digits, back to default
    UNBOUND_N_RX_PORT=53
  fi


  if [ "$UNBOUND_TTL_MIN" -gt 1800 ] ; then
    # that could have had awful side effects
    UNBOUND_TTL_MIN=300
  fi


  if [ "$UNBOUND_B_MAN_CONF" -gt 0 ] ; then
    if [ -f /etc/unbound/unbound.conf ] ; then
      # You don't want UCI and use your own manual configuration
      # or with no base file whatever Unbound defaults are.
      cp -p /etc/unbound/unbound.conf $UNBOUND_CONFFILE
    fi


    # Don't want this being triggered. Maybe we could, but then the
    # base conf you provide would need to be just right.
    UNBOUND_B_DNSMASQ=0

  else
    unbound_conf $cfg
  fi
}

##############################################################################

unbound_own () {
  # Debug UCI
  {
    echo "# $UNBOUND_CHECKFILE generated by UCI $( date )"
    echo
    set | grep ^UNBOUND_
  } > $UNBOUND_CHECKFILE


  if [ ! -f "$UNBOUND_CONFFILE" ] ; then
    # if somehow this happened
    touch $UNBOUND_CONFFILE
  fi


  # Ensure Access
  chown -R unbound:unbound $UNBOUND_VARDIR
  chmod 775 $UNBOUND_VARDIR
  chmod 664 $UNBOUND_VARDIR/*
}

##############################################################################

unbound_prepare() {
  # Make a home for Unbound in /var/lib/unbound
  unbound_mkdir

  # Load up the chunks of UCI
  config_load unbound
  config_foreach unbound_uci unbound

  # Unbound primary DNS, and dnsmasq side service DHCP-DNS (dnsmasq.sh)
  dnsmasq_link

  # Unbound needs chroot ownership
  unbound_own
}

##############################################################################

