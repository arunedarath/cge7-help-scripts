#!/usr/bin/expect

set command [lindex $argv 0]
set host "wti3.mvista.com"
set user "root"
set port "5"

if { $command == "off" } {
	puts "############### switching of port $port at $host ################"

	spawn telnet -l $user $host
	expect "NPS>"
	send "/off $port\r"
	expect "Sure? (Y/N):"
	send "Y\r"
	expect "NPS>"
	send "/x\r"
	expect "Sure? (Y/N):"
	send "Y\r"
} else {
	puts "############## Power cycle port $port at $host ################"

	spawn telnet -l $user $host
	expect "NPS>"
	send "/off $port\r"
	expect "Sure? (Y/N):"
	send "Y\r"
	expect "NPS>"
	send "/on $port\r"
	expect "Sure? (Y/N):"
	send "Y\r"
	expect "NPS>"
	send "/x\r"
	expect "Sure? (Y/N):"
	send "Y\r"
}
