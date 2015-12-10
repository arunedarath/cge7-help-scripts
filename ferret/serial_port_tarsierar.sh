#!/usr/bin/expect
# Please contact achandran@mvista.com if found any problem using it.

log_user 0
set port_var [lindex $argv 0]

set server "tarsierar"
#Append 70 for tarsier ports"
set port "70$port_var"
set pid 0
set password "alterpathpm"
set tar_prompt "\[root@TarsierAr root\]"

puts "connecting to $server:$port\n"
spawn -noecho telnet $server $port
expect {
	"Connection closed by foreign host." {
		set rc [catch {exec grep -o "(pid=.*.)" << $expect_out(buffer)} output ]
		if { $rc == "0" } {
			set pid [ exec echo $output | cut -d= -f2- | cut -d) -f1 ];
		} else {
			puts "Unable to find the PID of the user"
		}
	}
}

if { $pid > 0 } {
	puts "ttyS$port_var is used by $pid in $server; Trying to connect by closing the existing user"
	spawn ssh -l root $server
	sleep 1
	expect {
		"Password: " {
			send "$password\r";
			exp_continue;
		}

		"$tar_prompt" {
			expect "$tar_prompt"
			send "kill -9 $pid\r"
			sleep 2
			expect "$tar_prompt"
			send_user "Successfully logged into $server to kill $pid\n";
			send "exit\r"
			expect "Connection to tarsierar closed."
		}
	}

#Now nobody is using the serial respawn
spawn -noecho telnet $server $port
}

expect "Connected to qafarmtx30-68.mvista.com."
send_user "Sucess!!! Press Enter\n"
interact
