package require udp

namespace eval udp_transport {
    variable socket ""
    variable callback ""

    proc init {port cb} {
        variable socket
        variable callback
        set callback $cb
        set socket [udp_open $port]
        fconfigure $socket -buffering none -translation binary
        fileevent $socket readable [list [namespace current]::receive]
        return $socket
    }

    proc receive {} {
        variable socket
        variable callback
        set data [read $socket]
        set peer [udp_conf $socket -peer]
        if {[llength $peer] < 2} {
            # Might happen if not connected or something
            return
        }
        set addr [lindex $peer 0]
        set port [lindex $peer 1]
        if {$callback ne ""} {
            if {[catch {$callback $addr $port $data} err]} {
                puts stderr "Error in callback: $err\n$::errorInfo"
            }
        }
    }

    proc send {addr port data} {
        variable socket
        if {[catch {
            udp_conf $socket $addr $port
            puts -nonewline $socket $data
        } err]} {
            puts stderr "Error sending to $addr:$port - $err"
        }
    }
}
