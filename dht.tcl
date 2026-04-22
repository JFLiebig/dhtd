source kademlia.tcl
source udp_transport.tcl

proc main {port {bootstrap_host ""} {bootstrap_port ""}} {
    # Generate a random ID
    set myid ""
    for {set i 0} {$i < 20} {incr i} {
        append myid [format %c [expr {int(rand() * 256)}]]
    }

    kademlia::init $myid
    puts "Node ID: [binary encode hex $myid]"

    udp_transport::init $port kademlia::handle_message
    puts "Listening on port $port"

    if {$bootstrap_host ne ""} {
        puts "Bootstrapping with $bootstrap_host:$bootstrap_port"
        kademlia::send_ping $bootstrap_host $bootstrap_port
        kademlia::send_find_node $bootstrap_host $bootstrap_port $myid
    }

    # Enter event loop
    vwait forever
}

if {$argc < 1} {
    puts "Usage: tclsh dht.tcl <port> [<bootstrap_host> <bootstrap_port>]"
} else {
    main {*}$argv
}
