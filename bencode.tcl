namespace eval bencode {
    proc encode_string {s} {
        return "[string length $s]:$s"
    }

    proc encode_int {i} {
        return "i${i}e"
    }

    proc encode_list {l} {
        set res "l"
        foreach item $l {
            append res [encode $item]
        }
        append res "e"
        return $res
    }

    proc encode_dict {d} {
        set res "d"
        foreach key [lsort [dict keys $d]] {
            append res [encode_string $key]
            append res [encode [dict get $d $key]]
        }
        append res "e"
        return $res
    }

    proc encode {value} {
        set type [lindex $value 0]
        set val [lindex $value 1]
        switch -- $type {
            I { return [encode_int $val] }
            S { return [encode_string $val] }
            L { return [encode_list $val] }
            D { return [encode_dict $val] }
            default {
                # Fallback heuristics for convenience
                if {[string is integer -strict $value]} {
                    return [encode_int $value]
                }
                return [encode_string $value]
            }
        }
    }

    proc decode {data_var} {
        upvar 1 $data_var data
        set char [string index $data 0]
        if {$char eq "i"} {
            set end [string first "e" $data]
            if {$end == -1} { error "Truncated integer" }
            set val [string range $data 1 [expr {$end - 1}]]
            set data [string range $data [expr {$end + 1}] end]
            return [list I $val]
        } elseif {$char eq "l"} {
            set data [string range $data 1 end]
            set list {}
            while {[string index $data 0] ne "e"} {
                if {[string length $data] == 0} { error "Truncated list" }
                lappend list [decode data]
            }
            set data [string range $data 1 end]
            return [list L $list]
        } elseif {$char eq "d"} {
            set data [string range $data 1 end]
            set dict [dict create]
            while {[string index $data 0] ne "e"} {
                if {[string length $data] == 0} { error "Truncated dict" }
                set key_obj [decode data]
                if {[lindex $key_obj 0] ne "S"} { error "Dict key must be string" }
                set key [lindex $key_obj 1]
                set val [decode data]
                dict set dict $key $val
            }
            set data [string range $data 1 end]
            return [list D $dict]
        } elseif {[string is digit -strict $char]} {
            set colon [string first ":" $data]
            if {$colon == -1} { error "Invalid string length" }
            set len [string range $data 0 [expr {$colon - 1}]]
            set val [string range $data [expr {$colon + 1}] [expr {$colon + $len}]]
            set data [string range $data [expr {$colon + $len + 1}] end]
            return [list S $val]
        } else {
            error "Unknown bencode type at: [string range $data 0 10]"
        }
    }
}
