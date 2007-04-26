#!/bin/bash

#
#  Copyright Red Hat, Inc. 2004
#  Copyright Mission Critical Linux, Inc. 2000
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License as published by the
#  Free Software Foundation; either version 2, or (at your option) any
#  later version.
#
#  This program is distributed in the hope that it will be useful, but
#  WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#  General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; see the file COPYING.  If not, write to the
#  Free Software Foundation, Inc.,  675 Mass Ave, Cambridge, 
#  MA 02139, USA.
#

#
# IPv4/IPv6 address management using new /sbin/ifcfg instead of 
# ifconfig utility.
#

LC_ALL=C
LANG=C
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export LC_ALL LANG PATH

# Grab nfs lock tricks if available
export NFS_TRICKS=1
if [ -f "$(dirname $0)/svclib_nfslock" ]; then
	. $(dirname $0)/svclib_nfslock
	NFS_TRICKS=0
fi

. $(dirname $0)/ocf-shellfuncs


meta_data()
{
    cat <<EOT
<?xml version="1.0" ?>
<resource-agent version="rgmanager 2.0" name="ip">
    <version>1.0</version>

    <longdesc lang="en">
        This is an IP address.  Both IPv4 and IPv6 addresses are supported,
        as well as NIC link monitoring for each IP address.
    </longdesc>
    <shortdesc lang="en">
        This is an IP address.
    </shortdesc>

    <parameters>
        <parameter name="address" unique="1" primary="1">
            <longdesc lang="en">
                IPv4 or IPv6 address to use as a virtual IP
                resource.
            </longdesc>

            <shortdesc lang="en">
                IP Address
            </shortdesc>

	    <content type="string"/>
        </parameter>

        <parameter name="family">
            <longdesc lang="en">
                IPv4 or IPv6 address protocol family.
            </longdesc>

            <shortdesc lang="en">
                Family
            </shortdesc>

            <!--
            <val>auto</val>
            <val>inet</val>
            <val>inet6</val>
            -->
            <content type="string"/>
        </parameter>

        <parameter name="monitor_link">
            <longdesc lang="en">
                Enabling this causes the status check to fail if
                the link on the NIC to which this IP address is
                bound is not present.
            </longdesc>
            <shortdesc lang="en">
                Monitor NIC Link
            </shortdesc>
            <content type="boolean" default="1"/>
        </parameter>

	<parameter name="nfslock" inherit="service%nfslock">
	    <longdesc lang="en">
	        If set and unmounting the file system fails, the node will
		try to kill lockd and issue reclaims across all remaining
		network interface cards.
	    </longdesc>
	    <shortdesc lang="en">
	        Enable NFS lock workarounds
	    </shortdesc>
	    <content type="boolean"/>
	</parameter>

    </parameters>

    <actions>
        <action name="start" timeout="20"/>
        <action name="stop" timeout="20"/>
	<!-- No recover action.  If the IP address is not useable, then
	     resources may or may not depend on it.  If it's been 
	     deconfigured, resources using it are in a bad state. -->

	<!-- Checks to see if the IP is up and (optionally) the link is
	     working -->
        <action name="status" interval="20" timeout="10"/>
        <action name="monitor" interval="20" timeout="10"/>

	<!-- Checks to see if we can ping the IP address locally -->
        <action name="status" depth="10" interval="60" timeout="20"/>
        <action name="monitor" depth="10" interval="60" timeout="20"/>

        <action name="meta-data" timeout="20"/>
        <action name="validate-all" timeout="20"/>
    </actions>

    <special tag="rgmanager">
	<attributes maxinstances="1"/>
	<child type="nfsclient" forbid="1"/>
	<child type="nfsexport" forbid="1"/>
    </special>
</resource-agent>
EOT
}


verify_address()
{
	# XXX TBD
	return 0
}


verify_all()
{
	# XXX TBD
	return 0
}


#
# Expand an IPv6 address.
#
ipv6_expand()
{
	typeset addr=$1
	typeset maskbits
	typeset -i x
	
	maskbits=${addr/*\//}
	if [ "$maskbits" = "$addr" ]; then
		maskbits=""
	else
		# chop off mask bits
		addr=${addr/\/*/}
	fi

	# use space as placeholder
	addr=${addr/::/\ }

	# get rid of colons
	addr=${addr//:/}

	# add in zeroes where the doublecolon was
	len=$((${#addr}-1))
	zeroes=
	while [ $len -lt 32 ]; do
		zeroes="0$zeroes"
		((len++))
	done
	addr=${addr/\ /$zeroes}

	# probably a better way to do this
	for (( x=0; x < ${#addr} ; x++)); do
		naddr=$naddr${addr:x:1}

		if (( x < (${#addr} - 1) && x%4 == 3)); then
			naddr=$naddr:
		fi
	done

	if [ -n "$maskbits" ]; then
		echo "$naddr/$maskbits"
		return 0
	fi

	echo "$naddr"
	return 0
}


#
# see if two ipv6 addrs are in the same subnet
#
ipv6_same_subnet()
{
	declare addrl=$1
	declare addrr=$2
	declare m=$3 
	declare r x llsb rlsb

	if [ $# -lt 2 ]; then
		ocf_log err "usage: ipv6_same_subnet addr1 addr2 [mask]"
		return 255
	fi

	if [ -z "$m" ]; then
		m=${addrl/*\//}

		[ -n "$m" ] || return 1

	fi

	if [ "${addrr}" != "${addrr/*\//}" ] &&
	   [ "$m" != "${addrr/*\//}" ]; then
		return 1
	fi

	addrl=${addrl/\/*/}
	if [ ${#addrl} -lt 39 ]; then
		addrl=$(ipv6_expand $addrl)
	fi

	addrr=${addrr/\/*/}
	if [ ${#addrr} -lt 39 ]; then
		addrr=$(ipv6_expand $addrr)
	fi

	# Calculate the amount to compare directly
	x=$(($m/4+$m/16-(($m%4)==0)))

	# and the remaining number of bits
	r=$(($m%4))

	if [ $r -ne 0 ]; then
		# If we have any remaining bits, we will need to compare
		# them later.  Get them now.
		llsb=`printf "%d" 0x${addrl:$x:1}`
		rlsb=`printf "%d" 0x${addrr:$x:1}`

		# One less byte to compare directly, please
		((--x))
	fi
	
	# direct (string comparison) to see if they are equal
	if [ "${addrl:0:$x}" != "${addrr:0:$x}" ]; then
		return 1
	fi

	case $r in
	0)
		return 0
		;;
	1)	
		[ $(($llsb & 8)) -eq $(($rlsb & 8)) ]
		return $?
		;;
	2)
		[ $(($llsb & 12)) -eq $(($rlsb & 12)) ]
		return $?
		;;
	3)
		[ $(($llsb & 14)) -eq $(($rlsb & 14)) ]
		return $?
		;;
	esac

	return 1
}


ipv4_same_subnet()
{
	declare addrl=$1
	declare addrr=$2
	declare m=$3 
	declare r x llsb rlsb

	if [ $# -lt 2 ]; then
		ocf_log err "usage: ipv4_same_subnet current_addr new_addr [maskbits]"
		return 255
	fi


	#
	# Chop the netmask off of the ipaddr:
	# e.g. 1.2.3.4/22 -> 22
	#
	if [ -z "$m" ]; then
		m=${addrl/*\//}
		[ -n "$m" ] || return 1
	fi

	#
	# Check to see if there was a subnet mask provided on the
	# new IP address.  If there was one and it does not match
	# our expected subnet mask, we are done.
	#
	if [ "${addrr}" != "${addrr/\/*/}" ] &&
	   [ "$m" != "${addrr/*\//}" ]; then
		return 1
	fi

	#
	# Chop off subnet bits for good.
	#
	addrl=${addrl/\/*/}
	addrr=${addrr/\/*/}

	#
	# Remove '.' characters from dotted decimal notation and save
	# in arrays. i.e.
	#
	#	192.168.1.163 -> array[0] = 192
	#	                 array[1] = 168
	#	                 array[2] = 1
	#	                 array[3] = 163
	#

	let x=0
	for quad in ${addrl//./\ }; do
		ip1[((x++))]=$quad
	done

	x=0
	for quad in ${addrr//./\ }; do
		ip2[((x++))]=$quad
	done

	x=0

	while [ $m -ge 8 ]; do
		((m-=8))
		if [ ${ip1[x]} -ne ${ip2[x]} ]; then
			return 1
		fi
		((x++))
	done

	case $m in
	0)
		return 0
		;;
	1)	
		[ $((${ip1[x]} & 128)) -eq $((${ip2[x]} & 128)) ]
		return $?
		;;
	2)
		[ $((${ip1[x]} & 192)) -eq $((${ip2[x]} & 192)) ]
		return $?
		;;
	3)
		[ $((${ip1[x]} & 224)) -eq $((${ip2[x]} & 224)) ]
		return $?
		;;
	4)
		[ $((${ip1[x]} & 240)) -eq $((${ip2[x]} & 240)) ]
		return $?
		;;
	5)
		[ $((${ip1[x]} & 248)) -eq $((${ip2[x]} & 248)) ]
		return $?
		;;
	6)
		[ $((${ip1[x]} & 252)) -eq $((${ip2[x]} & 252)) ]
		return $?
		;;
	7)
		[ $((${ip1[x]} & 254)) -eq $((${ip2[x]} & 254)) ]
		return $?
		;;
	esac

	return 1
}


ipv6_list_interfaces()
{
	declare idx dev ifaddr
	declare ifaddr_exp
	
	while read idx dev ifaddr; do
	    
		isSlave $dev
		if [ $? -ne 2 ]; then
			continue
		fi
		
		idx=${idx/:/}
		
		ifaddr_exp=$(ipv6_expand $ifaddr)
		
		echo $dev ${ifaddr_exp/\/*/} ${ifaddr_exp/*\//}
		
	done < <(/sbin/ip -o -f inet6 addr | awk '{print $1,$2,$4}')

	return 0
}


#
# Find slaves for a bonded interface
#
findSlaves()
{
	declare mastif=$1
	declare line
	declare intf
	declare interfaces

	if [ -z "$mastif" ]; then
		ocf_log err "usage: findSlaves <master I/F>"
		return $OCF_ERR_ARGS
	fi

	line=$(/sbin/ip link list dev $mastif | grep "<.*MASTER.*>")
	if [ $? -ne 0 ]; then
		ocf_log err "Error determining status of $mastif"
		return $OCF_ERR_GENERIC
	fi

	if [ -z "`/sbin/ip link list dev $mastif | grep \"<.*MASTER.*>\"`" ]
	then
		ocf_log err "$mastif is not a master device"
		return $OCF_ERR_GENERIC
	fi

       ## Strip possible VLAN (802.1q) suffixes 
       ##  - Roland Gadinger <roland.gadinger@beko.at> 
       mastif=${mastif%%.*} 

	while read line; do
		set - $line
		while [ $# -gt 0 ]; do
			case $1 in
			eth*:)
				interfaces="${1/:/} $interfaces"
				continue 2
				;;
			esac
			shift
		done
	done < <( /sbin/ip link list | grep "master $mastif" )

	echo $interfaces
}


isSlave()
{
	declare intf=$1
	declare line

	if [ -z "$intf" ]; then
		ocf_log err "usage: isSlave <I/F>"
		return $OCF_ERR_ARGS
	fi

	line=$(/sbin/ip link list dev $intf)
	if [ $? -ne 0 ]; then
		ocf_log err "$intf not found"
		return $OCF_ERR_GENERIC
	fi

	if [ "$line" = "${line/<*SLAVE*>/}" ]; then
		return 2
	fi

	# Yes, it is a slave device.  Ignore.
	return 0
}


# 
# Check if interface is in UP state
#
interface_up()
{
       declare intf=$1
       
       if [ -z "$intf" ]; then
		ocf_log err "usage: interface_up <I/F>"
		return 1
       fi
       
       line=$(/sbin/ip -o link show up dev $intf 2> /dev/null)
       [ -z "$line" ] && return 2
       
       return 0
}


ethernet_link_up()
{
	declare linkstate=$(ethtool $1 | grep "Link detected:" |\
			    awk '{print $3}')
	
	[ -n "$linkstate" ] || return 0

	case $linkstate in
	yes)
		return 0
		;;
	*)
		return 1
		;;
	esac
	
	return 1
}


#
# Checks the physical link status of an ethernet or bonded interface.
#
network_link_up()
{
	declare slaves
	declare intf_arg=$1
	declare link_up=1		# Assume link down
	declare intf_test

	if [ -z "$intf_arg" ]; then
		ocf_log err "usage: network_link_up <intf>"
		return 1
	fi
	
	#
	# XXX assumes bond* interfaces are the bonding driver. (Fair
	# assumption on Linux, I think)
	#
	if [ "${intf_arg/bond/}" != "$intf_arg" ]; then
		
		#
		# Bonded driver.  Check link of all slaves for this interface.
		# If any link is up, the bonding driver is expected to route
		# traffic through that link.  Thus, the entire bonded link
		# is declared up.
		#
		slaves=$(findSlaves $intf_arg)
		if [ $? -ne 0 ]; then
			ocf_log err "Error finding slaves of $intf_arg"
			return 1
		fi
		for intf_test in $slaves; do
			ethernet_link_up $intf_test && link_up=0
		done
	else
		ethernet_link_up $intf_arg
		link_up=$?
	fi

	if [ $link_up -eq 0 ]; then
		ocf_log debug "Link for $intf_arg: Detected"
	else
		ocf_log warn "Link for $intf_arg: Not detected"
	fi

	return $link_up
}


ipv4_list_interfaces()
{
	declare idx dev ifaddr

	while read idx dev ifaddr; do
	        
		isSlave $dev
		if [ $? -ne 2 ]; then
			continue
		fi
		
		idx=${idx/:/}
		
		echo $dev ${ifaddr/\/*/} ${ifaddr/*\//}
		
	done < <(/sbin/ip -o -f inet addr | awk '{print $1,$2,$4}')
	
	return 0
}


#
# Add an IP address to our interface.
#
ipv6()
{
	declare dev maskbits
	declare addr=$2
	declare addr_exp=$(ipv6_expand $addr)
	
	while read dev ifaddr_exp maskbits; do 
	        if [ -z "$dev" ]; then
		        continue
		fi
		
		if [ "$1" = "add" ]; then
			ipv6_same_subnet $ifaddr_exp/$maskbits $addr_exp
			if [ $? -ne 0 ]; then
                                continue
                        fi
                        interface_up $dev
                        if [ $? -ne 0 ]; then
                                continue
                        fi
                        network_link_up $dev
                        if [ $? -ne 0 ]; then
                                continue
                        fi
			ocf_log info "Adding IPv6 address $addr to $dev"
		fi
		if [ "$1" = "del" ]; then
		        if [ "${addr_exp/\/*/}" != "$ifaddr_exp" ]; then
			        continue
			fi
			ocf_log info "Removing IPv6 address $addr from $dev"
                fi
		
		/sbin/ip -f inet6 addr $1 dev $dev $addr
		[ $? -ne 0 ] && return 1
		
		#
		# NDP should take of figuring out our new address.  Plus,
		# we do not have something (like arping) to do this for ipv6
		# anyway.
		# 
		# RFC 2461, section 7.2.6 states thusly:
		#
	   	# Note that because unsolicited Neighbor Advertisements do not
		# reliably update caches in all nodes (the advertisements might
		# not be received by all nodes), they should only be viewed as
		# a performance optimization to quickly update the caches in
		#  most neighbors. 
		#
		
		# Not sure if this is necessary for ipv6 either.
		file=$(which rdisc 2>/dev/null)
		if [ -f "$file" ]; then
		        killall -HUP rdisc || rdisc -fs
		fi
		
		return 0
	done < <(ipv6_list_interfaces)
	
	return 1
}


#
# Add an IP address to our interface.
#
ipv4()
{
	declare dev ifaddr maskbits
	declare addr=$2
	
	while read dev ifaddr maskbits; do
	        if [ -z "$dev" ]; then
		        continue
		fi

		if [ "$1" = "add" ]; then
		        ipv4_same_subnet $ifaddr/$maskbits $addr
			if [ $? -ne 0 ]; then
			        continue
			fi
		        interface_up $dev
			if [ $? -ne 0 ]; then
			        continue
			fi
			network_link_up $dev
			if [ $? -ne 0 ]; then
				continue
			fi
			ocf_log info "Adding IPv4 address $addr to $dev"
		fi
		if [ "$1" = "del" ]; then
			if [ "${addr/\/*/}" != "$ifaddr" ]; then
			        continue
			fi
			ocf_log info "Removing IPv4 address $addr from $dev"
		fi
		
		/sbin/ip -f inet addr $1 dev $dev $addr
		[ $? -ne 0 ] && return 1
		
        	#
	        # The following is needed only with ifconfig; ifcfg does it for us
        	#
		if [ "$1" = "add" ]; then
        		# do that freak arp thing
		    
 		        hwaddr=$(/sbin/ip -o link show $dev)
			hwaddr=${hwaddr/*link\/ether\ /}
			hwaddr=${hwaddr/\ \*/}
			
			addr=${addr/\/*/}
			ocf_log debug "Sending gratuitous ARP: $addr $hwaddr"
			arping -q -c 2 -U -I $dev $addr
		fi
		
		file=$(which rdisc 2>/dev/null)
		if [ -f "$file" ]; then
		        killall -HUP rdisc || rdisc -fs
		fi
		
		return 0
	done  < <(ipv4_list_interfaces)
	
	return 1
}


#
# Usage:
# ping_check <family> <address> [interface]
#
ping_check()
{
	declare ops="-c 1 -w 2"
	declare pingcmd=""

	if [ "$1" = "inet6" ]; then
		pingcmd="ping6"
	else
		pingcmd="ping"
	fi

	if [ -n "$3" ]; then 
		ops="$ops -I $3"
	fi

	return $($pingcmd $ops $2 &> /dev/null)
}


# 
# Usage:
# check_interface_up <family> <address>
#
check_interface_up()
{
	declare dev
	declare addr=${2/\/*/}

	dev=$(/sbin/ip -f $1 -o addr | grep " $addr/" | awk '{print $2}')
	if [ -z "$dev" ]; then
		return 1
	fi
	
	interface_up $dev
	return $?
}


# 
# Usage:
# address_configured <family> <address>
#
address_configured()
{
	declare line
	declare addr

	# Chop off maxk bits 
	addr=${2/\/*/}
        line=$(/sbin/ip -f $1 -o addr | grep " $addr/")

        if [ -z "$line" ]; then
		return 1
	fi
	return 0
}


#
# Usage:
# ip_op <family> <operation> <address> [quiet]
#
ip_op()
{
	declare dev
	declare rtr
	declare monitor_link
	declare addr=${3/\/*/}
	
	monitor_link="yes"
	if [ "${OCF_RESKEY_monitor_link}" = "no" ] ||
	    [ "${OCF_RESKEY_monitor_link}" = "0" ]; then
	        monitor_link="no"
	fi
	
	if [ "$2" = "status" ]; then

		ocf_log debug "Checking $3, Level $OCF_CHECK_LEVEL"
	
		dev=$(/sbin/ip -f $1 -o addr | grep " $addr/" | awk '{print $2}')
		if [ -z "$dev" ]; then
			ocf_log warn "$3 is not configured"
			return 1
		fi
		ocf_log debug "$3 present on $dev"
		
		if [ "$monitor_link" = "yes" ]; then
			if ! network_link_up $dev; then
		        	ocf_log warn "No link on $dev..."
				return 1
			fi
			ocf_log debug "Link detected on $dev"
		fi
		
		[ $OCF_CHECK_LEVEL -lt 10 ] && return 0
		if ! ping_check $1 $addr $dev; then
			ocf_log warn "Failed to ping $addr"
			return 1
		fi
		ocf_log debug "Local ping to $addr succeeded"
		
		return 0
	fi

	case $1 in
	inet)
		ipv4 $2 $3
		return $?
		;;
	inet6)
		ipv6 $2 $3
		return $?
		;;
	esac
	return 1
}


case ${OCF_RESKEY_family} in
inet)
	;;
inet6)
	;;
*)
	if [ "${OCF_RESKEY_address//:/}" != "${OCF_RESKEY_address}" ]; then
		export OCF_RESKEY_family=inet6
	else
		export OCF_RESKEY_family=inet
	fi
	;;
esac


if [ -z "$OCF_CHECK_LEVEL" ]; then
	OCF_CHECK_LEVEL=0
fi

if [ -z "$OCF_RESKEY_monitor_link" ]; then
        OCF_RESKEY_monitor_link="yes"
fi


case $1 in
start)
	if address_configured ${OCF_RESKEY_family} ${OCF_RESKEY_address}; then
		ocf_log debug "${OCF_RESKEY_address} already configured"
		exit 0
	fi
	ip_op ${OCF_RESKEY_family} add ${OCF_RESKEY_address}

	if [ $NFS_TRICKS -eq 0 ]; then
		if [ "$OCF_RESKEY_nfslock" = "yes" ] || \
	   	   [ "$OCF_RESKEY_nfslock" = "1" ]; then
			notify_list_broadcast /var/lib/nfs/statd
		fi
	fi

	exit $?
	;;
stop)
	if address_configured ${OCF_RESKEY_family} ${OCF_RESKEY_address}; then
		
		ip_op ${OCF_RESKEY_family} del ${OCF_RESKEY_address}

		# Make sure it's down
		if address_configured ${OCF_RESKEY_family} ${OCF_RESKEY_address}; then
			ocf_log err "Failed to remove ${OCF_RESKEY_address}"
			exit 1
		fi

		# XXX Let nfsd/lockd clear their queues; we hope to have a
		# way to enforce this in the future
		sleep 10
	else
		ocf_log debug "${OCF_RESKEY_address} is not configured"
	fi
	exit 0
	;;
status|monitor)
	ip_op ${OCF_RESKEY_family} status ${OCF_RESKEY_address}
	[ $? -ne 0 ] && exit $OCF_NOT_RUNNING
	
	check_interface_up ${OCF_RESKEY_family} ${OCF_RESKEY_address}
	exit $?
	;;
restart)
	$0 stop || exit $OCF_ERR_GENERIC
	$0 start || exit $OCF_ERR_GENERIC
	exit 0
	;;
meta-data)
	meta_data
	exit 0
	;;
validate-all|verify_all)
	verify_all
	exit $?
	;;
*)
	echo "usage: $0 {start|stop|status|monitor|restart|meta-data|validate-all}"
	exit $OCF_ERR_UNIMPLEMENTED
	;;
esac

