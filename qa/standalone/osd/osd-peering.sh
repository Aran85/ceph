#!/usr/bin/env bash
source $CEPH_ROOT/qa/standalone/ceph-helpers.sh

function run() {
    local dir=$1
    shift

    export CEPH_MON="127.0.0.1:7155" # git grep '\<7155\>' : there must be only one
    export CEPH_ARGS
    CEPH_ARGS+="--fsid=$(uuidgen) --auth-supported=none "
    CEPH_ARGS+="--mon-host=$CEPH_MON"

     local funcs=${@:-$(set | sed -n -e 's/^\(TEST_[0-9a-z_]*\) .*/\1/p')}
    for func in $funcs ; do
        $func $dir || return 1
    done
}

 function TEST_fast_info() {
    local dir=$1

    setup $dir || return 1
    run_mon $dir a --osd_pool_default_size=3 || return 1
    run_mgr $dir x || return 1
    run_osd $dir 0 || return 1
    run_osd $dir 1 || return 1

    ceph osd primary-affinity 1 10	# let osd.1 be primary
    ceph osd primary-affinity 0 0

    wait_for_clean || return 1

    ceph osd pool create rep 1 || return 1
    ceph osd pool set rep min_size 1 || return 1
    ceph osd set norecover || return 1

    rados -p rep put test /etc/hosts || return 1
    ceph daemon osd.1 config set objectstore_blackhole true || return 1

    timeout 10 rados -p rep put test /etc/hosts || return 1

    # let osd.0 & osd.1 shutdown 
    kill_daemons $dir STOP osd.0 || return 1
    kill_daemons $dir STOP osd.1 || return 1
    kill_daemons $dir KILL osd.0 || return 1
    kill_daemons $dir KILL osd.1 || return 1

    activate_osd $dir 1 || return 1
    sleep 10 # wait for pgs to go active

    activate_osd $dir 0 || return 1
    sleep 10 # wait for pgs to go active

    # let osd.0 & osd.1 shutdown 
    kill_daemons $dir STOP osd.0 || return 1
    kill_daemons $dir STOP osd.1 || return 1
    kill_daemons $dir KILL osd.0 || return 1
    kill_daemons $dir KILL osd.1 || return 1

    
    activate_osd $dir 0 || return 1
    sleep 10 # wait for pgs to go active
    activate_osd $dir 1 --osd-debug-im-sure-no-pg-ever-split || return 1
    sleep 10 # wait for pgs to go active

    ceph osd unset norecover || return 1
    wait_for_clean || return 1
}



 main osd-peering "$@"

 # Local Variables:
# compile-command: "cd ../.. ; make -j4 && test/osd/pg-split-merge.sh"
# End:
