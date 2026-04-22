source bencode.tcl

namespace eval kademlia {
    variable myid ""
    variable buckets {} ;# List of buckets
    variable k 8        ;# K-bucket size
    variable transactions [dict create]
    variable next_tid 0
    variable storage [dict create] ;# info_hash -> list of {addr port}

    proc init {id} {
        variable myid
        set myid $id
        variable buckets
        set first_id [string repeat "\x00" 20]
        set buckets [list [dict create first $first_id nodes {}]]
    }

    # XOR distance calculation (common bits)
    proc common_bits {id1 id2} {
        for {set i 0} {$i < 20} {incr i} {
            set c1 [scan [string index $id1 $i] %c]
            set c2 [scan [string index $id2 $i] %c]
            if {$c1 != $c2} {
                set xor [expr {$c1 ^ $c2}]
                set j 0
                while {($xor & 0x80) == 0} {
                    set xor [expr {($xor << 1) & 0xFF}]
                    incr j
                }
                return [expr {8 * $i + $j}]
            }
        }
        return 160
    }

    proc lowbit {id} {
        for {set i 19} {$i >= 0} {set i [expr {$i - 1}]} {
            set c [scan [string index $id $i] %c]
            if {$c != 0} {
                for {set j 7} {$j >= 0} {set j [expr {$j - 1}]} {
                    if {($c & (0x80 >> $j)) != 0} {
                        return [expr {8 * $i + $j}]
                    }
                }
            }
        }
        return -1
    }

    proc bucket_middle {first next_first} {
        set bit1 [lowbit $first]
        if {$next_first eq ""} {
            set bit2 -1
        } else {
            set bit2 [lowbit $next_first]
        }
        set bit [expr {[expr {$bit1 > $bit2 ? $bit1 : $bit2}] + 1}]
        if {$bit >= 160} { return "" }

        set mid_id $first
        set byte_idx [expr {$bit / 8}]
        set bit_idx [expr {$bit % 8}]
        set c [scan [string index $mid_id $byte_idx] %c]
        set c [expr {$c | (0x80 >> $bit_idx)}]
        set mid_id [string replace $mid_id $byte_idx $byte_idx [format %c $c]]
        return $mid_id
    }

    proc in_bucket {id first next_first} {
        if {[string compare $id $first] < 0} { return 0 }
        if {$next_first ne "" && [string compare $id $next_first] >= 0} { return 0 }
        return 1
    }

    proc find_bucket_idx {id} {
        variable buckets
        set i 0
        foreach b $buckets {
            set first [dict get $b first]
            set next_first ""
            if {$i + 1 < [llength $buckets]} {
                set next_first [dict get [lindex $buckets [expr {$i + 1}]] first]
            }
            if {[in_bucket $id $first $next_first]} {
                return $i
            }
            incr i
        }
        return [expr {[llength $buckets] - 1}]
    }

    proc new_node {id addr port} {
        variable myid
        variable k
        variable buckets
        if {$id eq $myid} return

        set b_idx [find_bucket_idx $id]
        set b [lindex $buckets $b_idx]
        set nodes [dict get $b nodes]

        set found 0
        set i 0
        foreach node $nodes {
            if {[dict get $node id] eq $id} {
                set nodes [lreplace $nodes $i $i]
                lappend nodes [dict create id $id addr $addr port $port time [clock seconds]]
                set found 1
                break
            }
            incr i
        }

        if {!$found} {
            if {[llength $nodes] < $k} {
                lappend nodes [dict create id $id addr $addr port $port time [clock seconds]]
            } else {
                set first [dict get $b first]
                set next_first ""
                if {$b_idx + 1 < [llength $buckets]} {
                    set next_first [dict get [lindex $buckets [expr {$i + 1}]] first]
                }
                if {[in_bucket $myid $first $next_first]} {
                    split_bucket $b_idx
                    new_node $id $addr $port
                    return
                }
            }
        }
        dict set b nodes $nodes
        set buckets [lreplace $buckets $b_idx $b_idx $b]
    }

    proc split_bucket {b_idx} {
        variable buckets
        set b [lindex $buckets $b_idx]
        set first [dict get $b first]
        set next_first ""
        if {$b_idx + 1 < [llength $buckets]} {
            set next_first [dict get [lindex $buckets [expr {$i + 1}]] first]
        }

        set mid_id [bucket_middle $first $next_first]
        if {$mid_id eq ""} return

        set new_b [dict create first $mid_id nodes {}]
        set old_nodes [dict get $b nodes]
        dict set b nodes {}

        set buckets [linsert [lreplace $buckets $b_idx $b_idx $b] [expr {$b_idx + 1}] $new_b]

        foreach n $old_nodes {
            new_node [dict get $n id] [dict get $n addr] [dict get $n port]
        }
    }

    proc get_closest_nodes {target count} {
        variable buckets
        set all_nodes {}
        foreach b $buckets {
            foreach n [dict get $b nodes] {
                lappend all_nodes $n
            }
        }
        set sorted_nodes [lsort -command [list [namespace current]::compare_dist $target] $all_nodes]
        return [lrange $sorted_nodes 0 [expr {$count - 1}]]
    }

    proc compare_dist {target n1 n2} {
        set d1 [common_bits $target [dict get $n1 id]]
        set d2 [common_bits $target [dict get $n2 id]]
        if {$d1 > $d2} { return -1 }
        if {$d1 < $d2} { return 1 }
        return 0
    }

    # --- RPC Handling ---

    proc handle_message {peer_addr peer_port data} {
        variable myid
        if {[catch {bencode::decode data} msg]} {
            return
        }
        set msg_dict [lindex $msg 1]
        if {![dict exists $msg_dict y]} return
        set y [lindex [dict get $msg_dict y] 1]
        set t [lindex [dict get $msg_dict t] 1]

        if {$y eq "q"} {
            set q [lindex [dict get $msg_dict q] 1]
            set a [lindex [dict get $msg_dict a] 1]
            set sender_id [lindex [dict get $a id] 1]
            new_node $sender_id $peer_addr $peer_port

            if {$q eq "ping"} {
                send_pong $peer_addr $peer_port $t
            } elseif {$q eq "find_node"} {
                set target [lindex [dict get $a target] 1]
                send_nodes_reply $peer_addr $peer_port $t $target
            } elseif {$q eq "get_peers"} {
                set info_hash [lindex [dict get $a info_hash] 1]
                send_get_peers_reply $peer_addr $peer_port $t $info_hash
            } elseif {$q eq "announce_peer"} {
                set info_hash [lindex [dict get $a info_hash] 1]
                set port [lindex [dict get $a port] 1]
                store_peer $info_hash $peer_addr $port
                send_pong $peer_addr $peer_port $t
            }
        } elseif {$y eq "r"} {
            set r [lindex [dict get $msg_dict r] 1]
            set sender_id [lindex [dict get $r id] 1]
            new_node $sender_id $peer_addr $peer_port
            puts "Received reply from [binary encode hex $sender_id]"
        }
    }

    proc send_pong {addr port t} {
        variable myid
        set r [dict create id [list S $myid]]
        set reply [dict create t [list S $t] y [list S "r"] r [list D $r]]
        udp_transport::send $addr $port [bencode::encode [list D $reply]]
    }

    proc send_nodes_reply {addr port t target} {
        variable myid
        set closest [get_closest_nodes $target 8]
        set nodes_str [encode_nodes $closest]
        set r [dict create id [list S $myid] nodes [list S $nodes_str]]
        set reply [dict create t [list S $t] y [list S "r"] r [list D $r]]
        udp_transport::send $addr $port [bencode::encode [list D $reply]]
    }

    proc send_get_peers_reply {addr port t info_hash} {
        variable myid
        variable storage
        set r [dict create id [list S $myid] token [list S "secret"]]
        if {[dict exists $storage $info_hash]} {
            set values {}
            foreach p [dict get $storage $info_hash] {
                lappend values [list S [encode_peer [lindex $p 0] [lindex $p 1]]]
            }
            dict set r values [list L $values]
        } else {
            set closest [get_closest_nodes $info_hash 8]
            dict set r nodes [list S [encode_nodes $closest]]
        }
        set reply [dict create t [list S $t] y [list S "r"] r [list D $r]]
        udp_transport::send $addr $port [bencode::encode [list D $reply]]
    }

    proc encode_nodes {nodes} {
        set nodes_str ""
        foreach n $nodes {
            set id [dict get $n id]
            set addr [dict get $n addr]
            set port [dict get $n port]
            set ip_parts [split $addr "."]
            append nodes_str [binary format a20c4S $id $ip_parts $port]
        }
        return $nodes_str
    }

    proc encode_peer {addr port} {
        set ip_parts [split $addr "."]
        return [binary format c4S $ip_parts $port]
    }

    proc store_peer {info_hash addr port} {
        variable storage
        set peers {}
        if {[dict exists $storage $info_hash]} {
            set peers [dict get $storage $info_hash]
        }
        lappend peers [list $addr $port]
        dict set storage $info_hash $peers
    }

    proc send_ping {addr port} {
        variable myid
        variable next_tid
        set t [format %04d $next_tid]
        incr next_tid
        set a [dict create id [list S $myid]]
        set q [dict create t [list S $t] y [list S "q"] q [list S "ping"] a [list D $a]]
        udp_transport::send $addr $port [bencode::encode [list D $q]]
    }

    proc send_find_node {addr port target} {
        variable myid
        variable next_tid
        set t [format %04d $next_tid]
        incr next_tid
        set a [dict create id [list S $myid] target [list S $target]]
        set q [dict create t [list S $t] y [list S "q"] q [list S "find_node"] a [list D $a]]
        udp_transport::send $addr $port [bencode::encode [list D $q]]
    }
}
