# ucm2tests.tcl
#
# Parses given ucm files (from ICU) to generate test data
# for encodings.
#
#  tclsh ucm2tests.tcl PATH_TO_ICU_UCM_DIRECTORY ?OUTPUTPATH?
#

namespace eval ucm {
    # No means to change these currently but ...
    variable outputPath
    variable outputChan
    variable errorChan stderr
    variable verbose 0

    # Map Tcl encoding name to ICU UCM file name
    variable encNameMap
    array set encNameMap {
        cp1250    glibc-CP1250-2.1.2
        cp1251    glibc-CP1251-2.1.2
        cp1252    glibc-CP1252-2.1.2
        cp1253    glibc-CP1253-2.1.2
        cp1254    glibc-CP1254-2.1.2
        cp1255    glibc-CP1255-2.1.2
        cp1256    glibc-CP1256-2.1.2
        cp1257    glibc-CP1257-2.1.2
        cp1258    glibc-CP1258-2.1.2
        gb1988    glibc-GB_1988_80-2.3.3
        iso8859-1 glibc-ISO_8859_1-2.1.2
        iso8859-2 glibc-ISO_8859_2-2.1.2
        iso8859-3 glibc-ISO_8859_3-2.1.2
        iso8859-4 glibc-ISO_8859_4-2.1.2
        iso8859-5 glibc-ISO_8859_5-2.1.2
        iso8859-6 glibc-ISO_8859_6-2.1.2
        iso8859-7 glibc-ISO_8859_7-2.3.3
        iso8859-8 glibc-ISO_8859_8-2.3.3
        iso8859-9 glibc-ISO_8859_9-2.1.2
        iso8859-10 glibc-ISO_8859_10-2.1.2
        iso8859-11 glibc-ISO_8859_11-2.1.2
        iso8859-13 glibc-ISO_8859_13-2.3.3
        iso8859-14 glibc-ISO_8859_14-2.1.2
        iso8859-15 glibc-ISO_8859_15-2.1.2
        iso8859-16 glibc-ISO_8859_16-2.3.3
    }

    # Array keyed by Tcl encoding name. Each element contains mapping of
    # Unicode code point -> byte sequence for that encoding as a flat list
    # (or dictionary). Both are stored as hex strings
    variable charMap

    # Array keyed by Tcl encoding name. List of invalid code sequences
    # each being a hex string.
    variable invalidCodeSequences

    # Array keyed by Tcl encoding name. List of unicode code points that are
    # not mapped, each being a hex string.
    variable unmappedCodePoints

    # The fallback character per encoding
    variable encSubchar
}

proc ucm::abort {msg} {
    variable errorChan
    puts $errorChan $msg
    exit 1
}
proc ucm::warn {msg} {
    variable errorChan
    puts $errorChan $msg
}
proc ucm::log {msg} {
    variable verbose
    if {$verbose} {
        variable errorChan
        puts $errorChan $msg
    }
}
proc ucm::print {s} {
    variable outputChan
    puts $outputChan $s
}

proc ucm::parse_SBCS {encName fd} {
    variable charMap
    variable invalidCodeSequences
    variable unmappedCodePoints

    set result {}
    while {[gets $fd line] >= 0} {
        if {[string match #* $line]} {
            continue
        }
        if {[string equal "END CHARMAP" [string trim $line]]} {
            break
        }
        if {![regexp {^\s*<U([[:xdigit:]]{4})>\s*((\\x[[:xdigit:]]{2})+)\s*(\|(0|1|2|3|4))} $line -> unichar bytes - - precision]} {
            error "Unexpected line parsing SBCS: $line"
        }
        set bytes [string map {\\x {}} $bytes]; # \xNN -> NN
        if {$precision eq "" || $precision eq "0"} {
            lappend result $unichar $bytes
        } else {
            # It is a fallback mapping - ignore
        }
    }
    set charMap($encName) $result

    # Find out invalid code sequences and unicode code points that are not mapped
    set valid {}
    set mapped {}
    foreach {unich bytes} $result {
        lappend mapped $unich
        lappend valid $bytes
    }
    set invalidCodeSequences($encName) {}
    for {set i 0} {$i <= 255} {incr i} {
        set hex [format %.2X $i]
        if {[lsearch -exact $valid $hex] < 0} {
            lappend invalidCodeSequences($encName) $hex
        }
    }

    set unmappedCodePoints($encName) {}
    for {set i 0} {$i <= 65535} {incr i} {
        set hex [format %.4X $i]
        if {[lsearch -exact $mapped $hex] < 0} {
            lappend unmappedCodePoints($encName) $hex
            # Only look for (at most) one below 256 and one above 1024
            if {$i < 255} {
                # Found one so jump past 8 bits
                set i 255
            } else {
                break
            }
        }
        if {$i == 255} {
            set i 1023
        }
    }
    lappend unmappedCodePoints($encName) D800 DC00 10000 10FFFF
}

proc ucm::generate_boilerplate {} {
    # Common procedures
    print {
# This file is automatically generated by ucm2tests.tcl.
# Edits will be overwritten on next generation.
#
# Generates tests comparing Tcl encodings to ICU.
# The generated file is NOT standalone. It should be sourced into a test script.

proc ucmConvertfromMismatches {enc map} {
    set mismatches {}
    foreach {unihex hex} $map {
        set unihex [string range 00000000$unihex end-7 end]; # Make 8 digits
        set unich [subst "\\U$unihex"]
        if {[encoding convertfrom -profile strict $enc [binary decode hex $hex]] ne $unich} {
            lappend mismatches "<[printable $unich],$hex>"
        }
    }
    return $mismatches
}
proc ucmConverttoMismatches {enc map} {
    set mismatches {}
    foreach {unihex hex} $map {
        set unihex [string range 00000000$unihex end-7 end]; # Make 8 digits
        set unich [subst "\\U$unihex"]
        if {[encoding convertto -profile strict $enc $unich] ne [binary decode hex $hex]} {
            lappend mismatches "<[printable $unich],$hex>"
        }
    }
    return $mismatches
}
if {[info commands printable] eq ""} {
    proc printable {s} {
        set print ""
        foreach c [split $s ""] {
            set i [scan $c %c]
            if {[string is print $c] && ($i <= 127)} {
                append print $c
            } elseif {$i <= 0xff} {
                append print \\x[format %02X $i]
            } elseif {$i <= 0xffff} {
                append print \\u[format %04X $i]
            } else {
                append print \\U[format %08X $i]
            }
        }
        return $print
    }
}
    }
} ; # generate_boilerplate

proc ucm::generate_tests {} {
    variable encNameMap
    variable charMap
    variable invalidCodeSequences
    variable unmappedCodePoints
    variable outputPath
    variable outputChan
    variable encSubchar

    if {[info exists outputPath]} {
        set outputChan [open $outputPath w]
        fconfigure $outputChan -translation lf
    } else {
        set outputChan stdout
    }

    array set tclNames {}
    foreach encName [encoding names] {
        set tclNames($encName) ""
    }

    generate_boilerplate
    foreach encName [lsort -dictionary [array names encNameMap]] {
        if {![info exists charMap($encName)]} {
            warn "No character map read for $encName"
            continue
        }
        unset tclNames($encName)

        # Print the valid tests
        print "\n#\n# $encName (generated from $encNameMap($encName))"
        print "\ntest encoding-convertfrom-ucmCompare-$encName {Compare against ICU UCM} -body \{"
        print "    ucmConvertfromMismatches $encName {$charMap($encName)}"
        print "\} -result {}"
        print "\ntest encoding-convertto-ucmCompare-$encName {Compare against ICU UCM} -body \{"
        print "    ucmConverttoMismatches $encName {$charMap($encName)}"
        print "\} -result {}"
        if {0} {
            # This will generate individual tests for every char
            # and test in lead, tail, middle, solo configurations
            # but takes considerable time
            print "lappend encValidStrings \{*\}\{"
            foreach {unich hex} $charMap($encName) {
                print "    $encName \\u$unich $hex {} {}"
            }
            print "\}; # $encName"
        }

        # Generate the invalidity checks
        print "\n# $encName - invalid byte sequences"
        print "lappend encInvalidBytes \{*\}\{"
        foreach hex $invalidCodeSequences($encName) {
            # Map XXXX... to \xXX\xXX...
            set uhex [regsub -all .. $hex {\\x\0}]
            set uhex \\U[string range 00000000$hex end-7 end]
            print "    $encName $hex tcl8    $uhex -1 {} {}"
            print "    $encName $hex replace \\uFFFD -1 {} {}"
            print "    $encName $hex strict  {}       0 {} {}"
        }
        print "\}; # $encName"

        print "\n# $encName - invalid byte sequences"
        print "lappend encUnencodableStrings \{*\}\{"
        if {[info exists encSubchar($encName)]} {
            set subchar $encSubchar($encName)
        } else {
            set subchar "3F"; # Tcl uses ? by default
        }
        foreach hex $unmappedCodePoints($encName) {
            set uhex \\U[string range 00000000$hex end-7 end]
            print "    $encName $uhex tcl8    $subchar -1 {} {}"
            print "    $encName $uhex replace $subchar -1 {} {}"
            print "    $encName $uhex strict  {}                      0 {} {}"
        }
        print "\}; # $encName"
    }

    if {[array size tclNames]} {
        warn "Missing encoding: [lsort [array names tclNames]]"
    }
    if {[info exists outputPath]} {
        close $outputChan
        unset outputChan
    }
}

proc ucm::parse_file {encName ucmPath} {
    variable charMap
    variable encSubchar

    set fd [open $ucmPath]
    try {
        # Parse the metadata
        unset -nocomplain state
        while {[gets $fd line] >= 0} {
            if {[regexp {<(code_set_name|mb_cur_max|mb_cur_min|uconv_class|subchar)>\s+(\S+)} $line -> key val]} {
                set state($key) $val
            } elseif {[regexp {^\s*CHARMAP\s*$} $line]} {
                set state(charmap) ""
                break
            } else {
                # Skip all else
            }
        }
        if {![info exists state(charmap)]} {
            abort "Error: $ucmPath has No CHARMAP line."
        }
        foreach key {code_set_name uconv_class} {
            if {[info exists state($key)]} {
                set state($key) [string trim $state($key) {"}]
            }
        }
        if {[info exists charMap($encName)]} {
            abort "Duplicate file for $encName ($path)"
        }
        if {![info exists state(uconv_class)]} {
            abort "Error: $ucmPath has no uconv_class definition."
        }
        if {[info exists state(subchar)]} {
            # \xNN\xNN.. -> NNNN..
            set encSubchar($encName) [string map {\\x {}} $state(subchar)]
        }
        switch -exact -- $state(uconv_class) {
            SBCS {
                if {[catch {
                    parse_SBCS $encName $fd
                } result]} {
                    abort "Could not process $ucmPath. $result"
                }
            }
            default {
                log "Skipping $ucmPath -- not SBCS encoding."
                return
            }
        }
    } finally {
        close $fd
    }
}

proc ucm::run {} {
    variable encNameMap
    variable outputPath
    switch [llength $::argv] {
        2 {set outputPath [lindex $::argv 1]}
        1 {}
        default {
            abort "Usage: [info nameofexecutable] $::argv0 path/to/icu/ucm/data ?outputfile?"
        }
    }
    foreach {encName fname} [array get encNameMap] {
        ucm::parse_file $encName [file join [lindex $::argv 0] ${fname}.ucm]
    }
    generate_tests
}

ucm::run
