#!/bin/sh
# EnvProbe collect script - GENERATED, DO NOT EDIT
# script_version=0.1.0
# bundle_version=2026.09.1
# build_hash=4b35ad66394431b3
# target=linux-universal
# items=17

set -u
LC_ALL=C
export LC_ALL
umask 077

# ---------------- global state ----------------
SCRIPT_VERSION='0.1.0'
BUNDLE_VERSION='2026.09.1'
BUILD_HASH='4b35ad66394431b3'
TARGET='linux-universal'
TIME_BUDGET_S=900
ITEM_TOTAL=17

OUT_BASE=$PWD
TMP=''
TMP_TRUNC=''
OUT_DIR=''
PKG_NAME=''
COLLECT_LOG=''
RC=0
no_timeout=false
TIMEOUT_MODE=none
STATUS_LINES=''
N_SUCCESS=0
N_SKIPPED=0
N_FAILED=0
FP=''
FP8=''
FP_NOHASH=false
HOSTNAME_S=''
TE_OS_FAMILY=unknown
TE_OS_ID=unknown
TE_OS_VER=''
TE_RAW_ID=''
TE_RAW_VERSION_ID=''
START_EPOCH=0
START_UTC=''
TZ_OFFSET=''
ITEM_STARTED=''
ITEM_ENDED=''
ITEM_STATUS=''

# ---------------- runtime library ----------------
have() { command -v "$1" >/dev/null 2>&1; }

TMP=$(mktemp "${TMPDIR:-/tmp}/envprobe.XXXXXXXX" 2>/dev/null) || TMP="${TMPDIR:-/tmp}/envprobe.collect.$$"
TMP_TRUNC="$TMP.trunc"
trap 'rm -f "$TMP" "$TMP_TRUNC" 2>/dev/null' EXIT

utc_now() {
  if have date; then
    date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
  fi
}

now_ms() {
  _ms=$(date +%s%3N 2>/dev/null)
  case "$_ms" in
    ''|*[!0-9]*) _ms=$(( $(date +%s 2>/dev/null || printf 0) * 1000 )) ;;
  esac
  printf '%s' "$_ms"
}

log() {
  if [ -n "$COLLECT_LOG" ]; then
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$*" >> "$COLLECT_LOG" 2>/dev/null
  fi
}

# b64e: stdin -> stdout, single base64 line. Prefer base64(1); pure POSIX fallback via od+awk.
b64e_od() {
  od -An -b | awk '
    BEGIN { tab = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" }
    {
      for (i = 1; i <= NF; i += 3) {
        b1 = $i
        b2 = $(i + 1)
        b3 = $(i + 2)
        printf "%s%s", substr(tab, int(b1 / 4) + 1, 1), substr(tab, (b1 % 4) * 16 + int(b2 / 16) + 1, 1)
        if (i + 1 <= NF) {
          printf "%s", substr(tab, (b2 % 16) * 4 + int(b3 / 64) + 1, 1)
          if (i + 2 <= NF) {
            printf "%s", substr(tab, b3 % 64 + 1, 1)
          } else {
            printf "%s", "="
            printf "%s", "="
          }
        } else {
          printf "%s", "="
          printf "%s", "="
        }
      }
    }'
  printf '\n'
}

b64e() {
  if have base64; then
    base64 2>/dev/null | tr -d '\r\n'
    printf '\n'
  else
    b64e_od
  fi
}

# sha256_file: print hash or nothing when no tool available (sha256sum > shasum -a 256 > openssl).
sha256_file() {
  if have sha256sum; then
    sha256sum "$1" 2>/dev/null | awk '{print $1; exit}'
  elif have shasum; then
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1; exit}'
  elif have openssl; then
    openssl dgst -sha256 "$1" 2>/dev/null | awk '{print $NF; exit}'
  fi
}

probe_timeout() {
  TIMEOUT_MODE=none
  if have timeout; then
    if timeout 1 true >/dev/null 2>&1; then
      TIMEOUT_MODE=std
    elif timeout -t 1 true >/dev/null 2>&1; then
      TIMEOUT_MODE=busybox_t
    fi
  fi
}

# run_variant <timeout_ms> <command>: stdout -> $TMP, stderr -> collect.log; sets global RC.
run_variant() {
  _tms=$1
  _cmd=$2
  _secs=$(( (_tms + 999) / 1000 ))
  [ "$_secs" -ge 1 ] || _secs=1
  rm -f "$TMP" 2>/dev/null
  no_timeout=false
  if [ "$TIMEOUT_MODE" = "std" ]; then
    timeout "$_secs" sh -c "$_cmd" > "$TMP" 2>> "$COLLECT_LOG"
    RC=$?
  elif [ "$TIMEOUT_MODE" = "busybox_t" ]; then
    timeout -t "$_secs" sh -c "$_cmd" > "$TMP" 2>> "$COLLECT_LOG"
    RC=$?
  else
    no_timeout=true
    ( eval "$_cmd" ) > "$TMP" 2>> "$COLLECT_LOG"
    RC=$?
  fi
}

first_mac() {
  for _d in /sys/class/net/*; do
    [ -f "$_d/address" ] || continue
    case "${_d##*/}" in lo|lo.*) continue ;; esac
    _a=$(cat "$_d/address" 2>/dev/null)
    case "$_a" in
      ''|*[!0-9a-fA-F:]*) continue ;;
      00:00:00:00:00:00) continue ;;
    esac
    printf '%s' "$_a"
    return 0
  done
  return 0
}

# ver_match <range-expr> <actual-major-version>: only major version comparison, POSIX arithmetic.
ver_match() {
  case "$2" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$1" in
    '>='*) _op=-ge; _n=${1#??} ;;
    '<='*) _op=-le; _n=${1#??} ;;
    '>'*) _op=-gt; _n=${1#?} ;;
    '<'*) _op=-lt; _n=${1#?} ;;
    '='*) _op=-eq; _n=${1#?} ;;
    *) _op=-eq; _n=$1 ;;
  esac
  case "$_n" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$_op" in
    -ge) [ "$2" -ge "$_n" ]; return ;;
    -le) [ "$2" -le "$_n" ]; return ;;
    -gt) [ "$2" -gt "$_n" ]; return ;;
    -lt) [ "$2" -lt "$_n" ]; return ;;
    *) [ "$2" -eq "$_n" ]; return ;;
  esac
}

# os_guard <family> <os_ids-space-separated-or-empty> <version-range-or-empty>
os_guard() {
  [ "$1" = "$TE_OS_FAMILY" ] || return 1
  if [ -n "$2" ]; then
    case " $2 " in
      *" $TE_OS_ID "*) ;;
      *) return 1 ;;
    esac
  fi
  if [ -n "$3" ]; then
    ver_match "$3" "$TE_OS_VER" || return 1
  fi
  return 0
}

# detect_os: sets TE_OS_FAMILY / TE_OS_ID / TE_OS_VER.
# os_id canonicalization: centos|rhel|rocky|almalinux -> rhel family; ubuntu/debian/kylin/uos/openeuler kept as-is.
detect_os() {
  TE_OS_FAMILY=linux
  TE_OS_ID=unknown
  TE_OS_VER=''
  _osr=''
  if [ -r /etc/os-release ]; then
    _osr=/etc/os-release
  elif [ -r /usr/lib/os-release ]; then
    _osr=/usr/lib/os-release
  fi
  if [ -n "$_osr" ]; then
    eval "$(awk -F= '$1 == "ID" || $1 == "VERSION_ID" { v = $2; gsub(/[^A-Za-z0-9._-]/, "", v); printf "TE_RAW_%s=%s\n", $1, v }' "$_osr" 2>/dev/null)"
  fi
  if [ -n "$TE_RAW_ID" ]; then
    case "$TE_RAW_ID" in
      centos|rhel|rocky|almalinux) TE_OS_ID=rhel ;;
      *) TE_OS_ID="$TE_RAW_ID" ;;
    esac

    TE_OS_VER=$(printf '%s' "$TE_RAW_VERSION_ID" | cut -d . -f 1)
  elif [ -r /etc/redhat-release ]; then
    TE_OS_ID=rhel
  fi
  log "detect_os: family=$TE_OS_FAMILY id=$TE_OS_ID ver=$TE_OS_VER"
}

seq_of() {
  case "$1" in
    'os.release') printf '001' ;;
    'os.hostname') printf '002' ;;
    'os.arch') printf '003' ;;
    'kernel.version') printf '004' ;;
    'kernel.glibc') printf '005' ;;
    'cpu.info') printf '006' ;;
    'memory.usage') printf '007' ;;
    'disk.usage') printf '008' ;;
    'storage.mounts') printf '009' ;;
    'network.interfaces') printf '010' ;;
    'network.listen.ports') printf '011' ;;
    'system.machine.id') printf '012' ;;
    'system.dmi.uuid') printf '013' ;;
    'pkg.installed') printf '014' ;;
    'pkg.local.repos') printf '015' ;;
    'service.init') printf '016' ;;
    'security.selinux') printf '017' ;;

    *) printf '999' ;;
  esac
}

record_status() {
  _rs_id=$1
  _rs_st=$2
  _rs_reason=$3
  _rs_rc=$4
  _rs_dur=$5
  _rs_esc=$(printf '%s' "$_rs_reason" | sed -e 's/\\/\\\\/g' -e 's/|/\\|/g' 2>/dev/null)
  if [ -n "$STATUS_LINES" ]; then
    STATUS_LINES="$STATUS_LINES
$_rs_id|$_rs_st|$_rs_esc|$_rs_rc|$_rs_dur"
  else
    STATUS_LINES="$_rs_id|$_rs_st|$_rs_esc|$_rs_rc|$_rs_dur"
  fi
  case "$_rs_st" in
    success) N_SUCCESS=$((N_SUCCESS + 1)) ;;
    failed) N_FAILED=$((N_FAILED + 1)) ;;
    *) N_SKIPPED=$((N_SKIPPED + 1)) ;;
  esac
}

budget_guard() {
  _el=$(( $(date +%s 2>/dev/null || printf '%s' "$START_EPOCH") - START_EPOCH ))
  if [ "$_el" -le "$TIME_BUDGET_S" ]; then
    return 0
  fi
  record_status "$1" skipped time_budget '' 0
  log "item $1 skipped: time budget ${TIME_BUDGET_S}s exceeded"
  return 1
}

# write_item <item_id> <ext> <max_bytes>: reads $TMP, truncates over limit, b64-encodes when needed.
write_item() {
  _w_id=$1
  _w_ext=$2
  _w_max=$3
  _w_seq=$(seq_of "$_w_id")
  _w_file="${OUT_DIR}/data/${_w_seq}_${_w_id}.${_w_ext}"
  _w_trunc=false
  _w_sz=0
  if [ -f "$TMP" ]; then
    _w_sz=$(wc -c < "$TMP" | tr -d '[:space:]')
    case "$_w_sz" in ''|*[!0-9]*) _w_sz=0 ;; esac
    if [ "$_w_sz" -gt "$_w_max" ]; then
      _w_trunc=true
      head -c "$_w_max" "$TMP" > "$TMP_TRUNC" 2>/dev/null || dd if="$TMP" of="$TMP_TRUNC" bs=1 count="$_w_max" 2>/dev/null
      mv -f "$TMP_TRUNC" "$TMP" 2>/dev/null
      _w_sz=$(wc -c < "$TMP" | tr -d '[:space:]')
      case "$_w_sz" in ''|*[!0-9]*) _w_sz=0 ;; esac
    fi
  fi
  _w_enc=plain
  _w_last_nl=false
  if [ "$_w_sz" -gt 0 ]; then
    _w_lc=$(wc -l < "$TMP" | tr -d '[:space:]')
    case "$_w_lc" in ''|*[!0-9]*) _w_lc=0 ;; esac
    if [ "$(tail -c 1 "$TMP" 2>/dev/null | wc -l | tr -d '[:space:]')" -ge 1 ]; then
      _w_last_nl=true
    fi
    _w_inner=$_w_lc
    if [ "$_w_last_nl" = true ]; then
      _w_inner=$((_w_lc - 1))
    fi
    if [ "$_w_inner" -gt 0 ] || grep -q '^###' "$TMP" 2>/dev/null; then
      _w_enc=b64
    fi
  fi
  {
    printf '### BEGIN %s\n' "$_w_id"
    printf 'rc=%s\n' "$RC"
    printf 'status=%s\n' "$ITEM_STATUS"
    printf 'started_at=%s\n' "$ITEM_STARTED"
    printf 'ended_at=%s\n' "$ITEM_ENDED"
    printf 'truncated=%s\n' "$_w_trunc"
    printf 'encoding=%s\n' "$_w_enc"
    if [ "$no_timeout" = true ]; then
      printf 'no_timeout=true\n'
    fi
    if [ "$_w_enc" = b64 ]; then
      b64e < "$TMP"
    elif [ "$_w_sz" -gt 0 ]; then
      cat "$TMP"
      if [ "$_w_last_nl" = false ]; then
        printf '\n'
      fi
    fi
    printf '### END\n'
  } > "$_w_file" 2>> "$COLLECT_LOG"
}

emit_fallback() {
  _e_id=$1
  _e_ext=$2
  _e_status=$3
  _e_reason=$4
  _e_dur=$5
  _e_seq=$(seq_of "$_e_id")
  _e_rc=''
  if [ "$_e_status" = confirmed_absent ]; then
    _e_rc=127
  fi
  {
    printf '### BEGIN %s\n' "$_e_id"
    printf 'rc=%s\n' "$_e_rc"
    printf 'status=%s\n' "$_e_status"
    printf 'started_at=%s\n' "$ITEM_STARTED"
    printf 'ended_at=%s\n' "$ITEM_ENDED"
    printf 'truncated=false\n'
    printf 'encoding=plain\n'
    printf '### END\n'
  } > "${OUT_DIR}/data/${_e_seq}_${_e_id}.${_e_ext}" 2>> "$COLLECT_LOG"
  record_status "$_e_id" "$_e_status" "$_e_reason" "$_e_rc" "$_e_dur"
}

compute_fingerprint() {
  _dmi=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null)
  _mid=''
  if [ -r /etc/machine-id ]; then
    _mid=$(cat /etc/machine-id 2>/dev/null)
  fi
  if [ -z "$_mid" ] && [ -r /var/lib/dbus/machine-id ]; then
    _mid=$(cat /var/lib/dbus/machine-id 2>/dev/null)
  fi
  _mac=$(first_mac)
  printf '%s%s%s%s' "$_dmi" "$_mid" "$HOSTNAME_S" "$_mac" > "$TMP"
  _h=$(sha256_file "$TMP")
  if [ -n "$_h" ]; then
    FP=$_h
    FP8=${_h%"${_h#????????}"}
  else
    FP="nohash-$HOSTNAME_S"
    FP8=$FP
    FP_NOHASH=true
  fi
}

# ---------------- generated item functions ----------------
# item: os.release (priority 10, seq 001) - 操作系统发行版
item_os_release() {
  _id='os.release'
  ITEM_STARTED=$(utc_now)
  _t0=$(now_ms)
  if os_guard 'linux' '' ''; then
    if [ -e '/etc/os-release' ]; then
      _attempt=0
      log 'item os.release: variant 1 matched'
      run_variant 10000 'cat /etc/os-release'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item os.release retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'cat /etc/os-release'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" kv 4096
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item os.release done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    elif [ -e '/etc/redhat-release' ]; then
      _attempt=0
      log 'item os.release: variant 2 matched'
      run_variant 10000 'cat /etc/redhat-release'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item os.release retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'cat /etc/redhat-release'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" kv 4096
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item os.release done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    else
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      emit_fallback "$_id" kv skipped 'no os-release or redhat-release' "$_DUR"
      log "item os.release: fallback skipped 'no os-release or redhat-release'"
    fi
  else
    ITEM_ENDED=$(utc_now)
    _DUR=$(( $(now_ms) - _t0 ))
    emit_fallback "$_id" kv skipped 'no os-release or redhat-release' "$_DUR"
    log "item os.release: fallback skipped 'no os-release or redhat-release'"
  fi
}

# item: os.hostname (priority 20, seq 002) - 主机名
item_os_hostname() {
  _id='os.hostname'
  ITEM_STARTED=$(utc_now)
  _t0=$(now_ms)
  if os_guard 'linux' '' ''; then
    if have 'hostname'; then
      _attempt=0
      log 'item os.hostname: variant 1 matched'
      run_variant 10000 'hostname'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item os.hostname retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'hostname'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" kv 1024
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item os.hostname done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    else
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      emit_fallback "$_id" kv skipped 'no variant matched' "$_DUR"
      log "item os.hostname: fallback skipped 'no variant matched'"
    fi
  else
    ITEM_ENDED=$(utc_now)
    _DUR=$(( $(now_ms) - _t0 ))
    emit_fallback "$_id" kv skipped 'no variant matched' "$_DUR"
    log "item os.hostname: fallback skipped 'no variant matched'"
  fi
}

# item: os.arch (priority 30, seq 003) - 系统架构
item_os_arch() {
  _id='os.arch'
  ITEM_STARTED=$(utc_now)
  _t0=$(now_ms)
  if os_guard 'linux' '' ''; then
    if have 'uname'; then
      _attempt=0
      log 'item os.arch: variant 1 matched'
      run_variant 10000 'uname -m'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item os.arch retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'uname -m'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" kv 1024
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item os.arch done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    else
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      emit_fallback "$_id" kv skipped 'no variant matched' "$_DUR"
      log "item os.arch: fallback skipped 'no variant matched'"
    fi
  else
    ITEM_ENDED=$(utc_now)
    _DUR=$(( $(now_ms) - _t0 ))
    emit_fallback "$_id" kv skipped 'no variant matched' "$_DUR"
    log "item os.arch: fallback skipped 'no variant matched'"
  fi
}

# item: kernel.version (priority 40, seq 004) - 内核版本
item_kernel_version() {
  _id='kernel.version'
  ITEM_STARTED=$(utc_now)
  _t0=$(now_ms)
  if os_guard 'linux' '' ''; then
    if have 'uname'; then
      _attempt=0
      log 'item kernel.version: variant 1 matched'
      run_variant 10000 'uname -r'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item kernel.version retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'uname -r'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" kv 1024
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item kernel.version done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    else
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      emit_fallback "$_id" kv skipped 'no variant matched' "$_DUR"
      log "item kernel.version: fallback skipped 'no variant matched'"
    fi
  else
    ITEM_ENDED=$(utc_now)
    _DUR=$(( $(now_ms) - _t0 ))
    emit_fallback "$_id" kv skipped 'no variant matched' "$_DUR"
    log "item kernel.version: fallback skipped 'no variant matched'"
  fi
}

# item: kernel.glibc (priority 50, seq 005) - glibc 版本
item_kernel_glibc() {
  _id='kernel.glibc'
  ITEM_STARTED=$(utc_now)
  _t0=$(now_ms)
  if os_guard 'linux' '' ''; then
    if have 'getconf'; then
      _attempt=0
      log 'item kernel.glibc: variant 1 matched'
      run_variant 10000 'getconf GNU_LIBC_VERSION'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item kernel.glibc retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'getconf GNU_LIBC_VERSION'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" kv 2048
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item kernel.glibc done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    else
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      emit_fallback "$_id" kv skipped 'getconf not available' "$_DUR"
      log "item kernel.glibc: fallback skipped 'getconf not available'"
    fi
  else
    ITEM_ENDED=$(utc_now)
    _DUR=$(( $(now_ms) - _t0 ))
    emit_fallback "$_id" kv skipped 'getconf not available' "$_DUR"
    log "item kernel.glibc: fallback skipped 'getconf not available'"
  fi
}

# item: cpu.info (priority 60, seq 006) - CPU 信息
item_cpu_info() {
  _id='cpu.info'
  ITEM_STARTED=$(utc_now)
  _t0=$(now_ms)
  if os_guard 'linux' '' ''; then
    if [ -e '/proc/cpuinfo' ]; then
      _attempt=0
      log 'item cpu.info: variant 1 matched'
      run_variant 10000 'cat /proc/cpuinfo'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item cpu.info retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'cat /proc/cpuinfo'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" kv 8192
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item cpu.info done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    else
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      emit_fallback "$_id" kv skipped 'no variant matched' "$_DUR"
      log "item cpu.info: fallback skipped 'no variant matched'"
    fi
  else
    ITEM_ENDED=$(utc_now)
    _DUR=$(( $(now_ms) - _t0 ))
    emit_fallback "$_id" kv skipped 'no variant matched' "$_DUR"
    log "item cpu.info: fallback skipped 'no variant matched'"
  fi
}

# item: memory.usage (priority 70, seq 007) - 内存使用
item_memory_usage() {
  _id='memory.usage'
  ITEM_STARTED=$(utc_now)
  _t0=$(now_ms)
  if os_guard 'linux' '' ''; then
    if have 'free'; then
      _attempt=0
      log 'item memory.usage: variant 1 matched'
      run_variant 10000 'free -m'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item memory.usage retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'free -m'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" kv 2048
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item memory.usage done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    else
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      emit_fallback "$_id" kv skipped 'no variant matched' "$_DUR"
      log "item memory.usage: fallback skipped 'no variant matched'"
    fi
  else
    ITEM_ENDED=$(utc_now)
    _DUR=$(( $(now_ms) - _t0 ))
    emit_fallback "$_id" kv skipped 'no variant matched' "$_DUR"
    log "item memory.usage: fallback skipped 'no variant matched'"
  fi
}

# item: disk.usage (priority 80, seq 008) - 磁盘使用率
item_disk_usage() {
  _id='disk.usage'
  ITEM_STARTED=$(utc_now)
  _t0=$(now_ms)
  if os_guard 'linux' '' ''; then
    if have 'df'; then
      _attempt=0
      log 'item disk.usage: variant 1 matched'
      run_variant 10000 'df -P -k -T'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item disk.usage retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'df -P -k -T'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" tsv 65536
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item disk.usage done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    else
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      emit_fallback "$_id" tsv skipped 'no variant matched' "$_DUR"
      log "item disk.usage: fallback skipped 'no variant matched'"
    fi
  else
    ITEM_ENDED=$(utc_now)
    _DUR=$(( $(now_ms) - _t0 ))
    emit_fallback "$_id" tsv skipped 'no variant matched' "$_DUR"
    log "item disk.usage: fallback skipped 'no variant matched'"
  fi
}

# item: storage.mounts (priority 90, seq 009) - 挂载点
item_storage_mounts() {
  _id='storage.mounts'
  ITEM_STARTED=$(utc_now)
  _t0=$(now_ms)
  if os_guard 'linux' '' ''; then
    if [ -e '/proc/mounts' ]; then
      _attempt=0
      log 'item storage.mounts: variant 1 matched'
      run_variant 10000 'cat /proc/mounts'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item storage.mounts retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'cat /proc/mounts'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" kv 32768
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item storage.mounts done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    else
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      emit_fallback "$_id" kv skipped 'no variant matched' "$_DUR"
      log "item storage.mounts: fallback skipped 'no variant matched'"
    fi
  else
    ITEM_ENDED=$(utc_now)
    _DUR=$(( $(now_ms) - _t0 ))
    emit_fallback "$_id" kv skipped 'no variant matched' "$_DUR"
    log "item storage.mounts: fallback skipped 'no variant matched'"
  fi
}

# item: network.interfaces (priority 100, seq 010) - 网卡与地址
item_network_interfaces() {
  _id='network.interfaces'
  ITEM_STARTED=$(utc_now)
  _t0=$(now_ms)
  if os_guard 'linux' '' ''; then
    if have 'ip'; then
      _attempt=0
      log 'item network.interfaces: variant 1 matched'
      run_variant 10000 'ip -o addr show'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item network.interfaces retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'ip -o addr show'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" kv 131072
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item network.interfaces done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    elif have 'ifconfig'; then
      _attempt=0
      log 'item network.interfaces: variant 2 matched'
      run_variant 10000 'ifconfig -a'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item network.interfaces retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'ifconfig -a'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" kv 131072
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item network.interfaces done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    else
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      emit_fallback "$_id" kv skipped 'neither ip nor ifconfig available' "$_DUR"
      log "item network.interfaces: fallback skipped 'neither ip nor ifconfig available'"
    fi
  else
    ITEM_ENDED=$(utc_now)
    _DUR=$(( $(now_ms) - _t0 ))
    emit_fallback "$_id" kv skipped 'neither ip nor ifconfig available' "$_DUR"
    log "item network.interfaces: fallback skipped 'neither ip nor ifconfig available'"
  fi
}

# item: network.listen.ports (priority 110, seq 011) - 监听端口
item_network_listen_ports() {
  _id='network.listen.ports'
  ITEM_STARTED=$(utc_now)
  _t0=$(now_ms)
  if os_guard 'linux' '' ''; then
    if have 'ss'; then
      _attempt=0
      log 'item network.listen.ports: variant 1 matched'
      run_variant 10000 'ss -tulpn'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item network.listen.ports retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'ss -tulpn'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" kv 32768
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item network.listen.ports done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    elif have 'netstat'; then
      _attempt=0
      log 'item network.listen.ports: variant 2 matched'
      run_variant 10000 'netstat -tulpn'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item network.listen.ports retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'netstat -tulpn'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" kv 32768
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item network.listen.ports done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    else
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      emit_fallback "$_id" kv skipped 'neither ss nor netstat available' "$_DUR"
      log "item network.listen.ports: fallback skipped 'neither ss nor netstat available'"
    fi
  else
    ITEM_ENDED=$(utc_now)
    _DUR=$(( $(now_ms) - _t0 ))
    emit_fallback "$_id" kv skipped 'neither ss nor netstat available' "$_DUR"
    log "item network.listen.ports: fallback skipped 'neither ss nor netstat available'"
  fi
}

# item: system.machine.id (priority 120, seq 012) - 机器标识
item_system_machine_id() {
  _id='system.machine.id'
  ITEM_STARTED=$(utc_now)
  _t0=$(now_ms)
  if os_guard 'linux' '' ''; then
    if [ -e '/etc/machine-id' ]; then
      _attempt=0
      log 'item system.machine.id: variant 1 matched'
      run_variant 10000 'cat /etc/machine-id'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item system.machine.id retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'cat /etc/machine-id'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" kv 2048
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item system.machine.id done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    elif [ -e '/var/lib/dbus/machine-id' ]; then
      _attempt=0
      log 'item system.machine.id: variant 2 matched'
      run_variant 10000 'cat /var/lib/dbus/machine-id'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item system.machine.id retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'cat /var/lib/dbus/machine-id'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" kv 2048
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item system.machine.id done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    else
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      emit_fallback "$_id" kv skipped 'no machine-id file' "$_DUR"
      log "item system.machine.id: fallback skipped 'no machine-id file'"
    fi
  else
    ITEM_ENDED=$(utc_now)
    _DUR=$(( $(now_ms) - _t0 ))
    emit_fallback "$_id" kv skipped 'no machine-id file' "$_DUR"
    log "item system.machine.id: fallback skipped 'no machine-id file'"
  fi
}

# item: system.dmi.uuid (priority 130, seq 013) - DMI 产品标识
item_system_dmi_uuid() {
  _id='system.dmi.uuid'
  ITEM_STARTED=$(utc_now)
  _t0=$(now_ms)
  if [ "$(id -u 2>/dev/null)" != 0 ]; then
    ITEM_ENDED=$(utc_now)
    _DUR=$(( $(now_ms) - _t0 ))
    emit_fallback "$_id" kv skipped 'requires_root' "$_DUR"
    log 'item system.dmi.uuid: skipped (requires_root)'
    return 0
  fi
  if os_guard 'linux' '' ''; then
    if [ -e '/sys/class/dmi/id/product_uuid' ]; then
      _attempt=0
      log 'item system.dmi.uuid: variant 1 matched'
      run_variant 10000 'cat /sys/class/dmi/id/product_uuid'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item system.dmi.uuid retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'cat /sys/class/dmi/id/product_uuid'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" kv 2048
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item system.dmi.uuid done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    else
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      emit_fallback "$_id" kv skipped 'dmi product_uuid not present (VM or non-x86)' "$_DUR"
      log "item system.dmi.uuid: fallback skipped 'dmi product_uuid not present (VM or non-x86)'"
    fi
  else
    ITEM_ENDED=$(utc_now)
    _DUR=$(( $(now_ms) - _t0 ))
    emit_fallback "$_id" kv skipped 'dmi product_uuid not present (VM or non-x86)' "$_DUR"
    log "item system.dmi.uuid: fallback skipped 'dmi product_uuid not present (VM or non-x86)'"
  fi
}

# item: pkg.installed (priority 140, seq 014) - 已安装软件包
item_pkg_installed() {
  _id='pkg.installed'
  ITEM_STARTED=$(utc_now)
  _t0=$(now_ms)
  if os_guard 'linux' '' ''; then
    if have 'rpm'; then
      _attempt=0
      log 'item pkg.installed: variant 1 matched'
      run_variant 60000 'rpm -qa'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item pkg.installed retry attempt $_attempt (rc=$RC)"
        run_variant 60000 'rpm -qa'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 60000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" lines 4194304
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item pkg.installed done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    elif have 'dpkg-query'; then
      _attempt=0
      log 'item pkg.installed: variant 2 matched'
      run_variant 60000 'dpkg-query -W'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item pkg.installed retry attempt $_attempt (rc=$RC)"
        run_variant 60000 'dpkg-query -W'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 60000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" lines 4194304
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item pkg.installed done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    else
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      emit_fallback "$_id" lines skipped 'no rpm or dpkg package database' "$_DUR"
      log "item pkg.installed: fallback skipped 'no rpm or dpkg package database'"
    fi
  else
    ITEM_ENDED=$(utc_now)
    _DUR=$(( $(now_ms) - _t0 ))
    emit_fallback "$_id" lines skipped 'no rpm or dpkg package database' "$_DUR"
    log "item pkg.installed: fallback skipped 'no rpm or dpkg package database'"
  fi
}

# item: pkg.local.repos (priority 150, seq 015) - 本地软件源配置
item_pkg_local_repos() {
  _id='pkg.local.repos'
  ITEM_STARTED=$(utc_now)
  _t0=$(now_ms)
  if os_guard 'linux' '' ''; then
    if [ -e '/etc/yum.repos.d' ]; then
      _attempt=0
      log 'item pkg.local.repos: variant 1 matched'
      run_variant 10000 'ls /etc/yum.repos.d'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item pkg.local.repos retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'ls /etc/yum.repos.d'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" lines 262144
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item pkg.local.repos done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    elif [ -e '/etc/apt/sources.list' ]; then
      _attempt=0
      log 'item pkg.local.repos: variant 2 matched'
      run_variant 10000 'cat /etc/apt/sources.list'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item pkg.local.repos retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'cat /etc/apt/sources.list'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" lines 262144
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item pkg.local.repos done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    elif [ -e '/etc/apt/sources.list.d' ]; then
      _attempt=0
      log 'item pkg.local.repos: variant 3 matched'
      run_variant 10000 'ls /etc/apt/sources.list.d'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item pkg.local.repos retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'ls /etc/apt/sources.list.d'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" lines 262144
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item pkg.local.repos done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    else
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      emit_fallback "$_id" lines confirmed_absent 'no yum or apt repo config found' "$_DUR"
      log "item pkg.local.repos: fallback confirmed_absent 'no yum or apt repo config found'"
    fi
  else
    ITEM_ENDED=$(utc_now)
    _DUR=$(( $(now_ms) - _t0 ))
    emit_fallback "$_id" lines confirmed_absent 'no yum or apt repo config found' "$_DUR"
    log "item pkg.local.repos: fallback confirmed_absent 'no yum or apt repo config found'"
  fi
}

# item: service.init (priority 160, seq 016) - 服务管理体系
item_service_init() {
  _id='service.init'
  ITEM_STARTED=$(utc_now)
  _t0=$(now_ms)
  if os_guard 'linux' '' ''; then
    if have 'systemctl'; then
      _attempt=0
      log 'item service.init: variant 1 matched'
      run_variant 10000 'systemctl get-default'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item service.init retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'systemctl get-default'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" kv 262144
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item service.init done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    elif have 'chkconfig'; then
      _attempt=0
      log 'item service.init: variant 2 matched'
      run_variant 10000 'chkconfig --list'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item service.init retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'chkconfig --list'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" kv 262144
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item service.init done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    else
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      emit_fallback "$_id" kv skipped 'no systemd or sysv service manager detected' "$_DUR"
      log "item service.init: fallback skipped 'no systemd or sysv service manager detected'"
    fi
  else
    ITEM_ENDED=$(utc_now)
    _DUR=$(( $(now_ms) - _t0 ))
    emit_fallback "$_id" kv skipped 'no systemd or sysv service manager detected' "$_DUR"
    log "item service.init: fallback skipped 'no systemd or sysv service manager detected'"
  fi
}

# item: security.selinux (priority 170, seq 017) - SELinux 状态
item_security_selinux() {
  _id='security.selinux'
  ITEM_STARTED=$(utc_now)
  _t0=$(now_ms)
  if os_guard 'linux' '' ''; then
    if have 'getenforce'; then
      _attempt=0
      log 'item security.selinux: variant 1 matched'
      run_variant 10000 'getenforce'
      while [ "$RC" -ne 0 ] && [ "$_attempt" -lt 0 ]; do
        if [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then break; fi
        _attempt=$((_attempt + 1))
        log "item security.selinux retry attempt $_attempt (rc=$RC)"
        run_variant 10000 'getenforce'
      done
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      if [ "$RC" -eq 0 ]; then
        ITEM_STATUS=success
        _reason=''
      elif [ "$no_timeout" = false ] && [ "$RC" -eq 124 ]; then
        ITEM_STATUS=failed
        _reason='timeout after 10000ms'
      else
        ITEM_STATUS=failed
        _reason="command exited rc=$RC"
      fi
      write_item "$_id" kv 1024
      record_status "$_id" "$ITEM_STATUS" "$_reason" "$RC" "$_DUR"
      log "item security.selinux done: status=$ITEM_STATUS rc=$RC dur=${_DUR}ms"
    else
      ITEM_ENDED=$(utc_now)
      _DUR=$(( $(now_ms) - _t0 ))
      emit_fallback "$_id" kv confirmed_absent 'selinux not installed' "$_DUR"
      log "item security.selinux: fallback confirmed_absent 'selinux not installed'"
    fi
  else
    ITEM_ENDED=$(utc_now)
    _DUR=$(( $(now_ms) - _t0 ))
    emit_fallback "$_id" kv confirmed_absent 'selinux not installed' "$_DUR"
    log "item security.selinux: fallback confirmed_absent 'selinux not installed'"
  fi
}


# ---------------- main ----------------
main() {
  START_EPOCH=$(date +%s 2>/dev/null || printf '%s' 0)
  case "$START_EPOCH" in
    ''|*[!0-9]*) START_EPOCH=0 ;;
  esac
  START_UTC=$(utc_now)
  TZ_OFFSET=$(date +%:z 2>/dev/null)
  case "$TZ_OFFSET" in
    *:*) ;;
    *) TZ_OFFSET=$(date +%z 2>/dev/null | sed -n 's/^\([-+][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/p') ;;
  esac
  HOSTNAME_S=$(hostname 2>/dev/null || uname -n 2>/dev/null || printf 'unknown')
  compute_fingerprint
  _ts=$(date +%Y%m%d-%H%M%S 2>/dev/null || printf 'notime')
  PKG_NAME="envprobe-$FP8-$_ts-$SCRIPT_VERSION"
  OUT_DIR="$OUT_BASE/$PKG_NAME"
  if ! mkdir -p "$OUT_DIR/data" "$OUT_DIR/logs" 2>/dev/null; then
    printf 'envprobe: cannot create output directory %s\n' "$OUT_DIR" >&2
    exit 1
  fi
  COLLECT_LOG="$OUT_DIR/logs/collect.log"
  : > "$COLLECT_LOG" 2>/dev/null
  probe_timeout
  log "envprobe start: pkg=$PKG_NAME build=$BUILD_HASH target=$TARGET timeout_mode=$TIMEOUT_MODE"
  log "fingerprint=$FP"
  detect_os
  # items in priority order
  budget_guard 'os.release' && item_os_release
  budget_guard 'os.hostname' && item_os_hostname
  budget_guard 'os.arch' && item_os_arch
  budget_guard 'kernel.version' && item_kernel_version
  budget_guard 'kernel.glibc' && item_kernel_glibc
  budget_guard 'cpu.info' && item_cpu_info
  budget_guard 'memory.usage' && item_memory_usage
  budget_guard 'disk.usage' && item_disk_usage
  budget_guard 'storage.mounts' && item_storage_mounts
  budget_guard 'network.interfaces' && item_network_interfaces
  budget_guard 'network.listen.ports' && item_network_listen_ports
  budget_guard 'system.machine.id' && item_system_machine_id
  budget_guard 'system.dmi.uuid' && item_system_dmi_uuid
  budget_guard 'pkg.installed' && item_pkg_installed
  budget_guard 'pkg.local.repos' && item_pkg_local_repos
  budget_guard 'service.init' && item_service_init
  budget_guard 'security.selinux' && item_security_selinux

  if [ -n "$STATUS_LINES" ]; then
    printf '%s\n' "$STATUS_LINES" > "$OUT_DIR/status.env"
  else
    : > "$OUT_DIR/status.env"
  fi
  {
    printf 'format_version=1\n'
    printf 'script_version=%s\n' "$SCRIPT_VERSION"
    printf 'build_hash=%s\n' "$BUILD_HASH"
    printf 'manifest_bundle_version=%s\n' "$BUNDLE_VERSION"
    printf 'collected_at_utc=%s\n' "$START_UTC"
    printf 'collected_tz_offset=%s\n' "$TZ_OFFSET"
    printf 'hostname=%s\n' "$HOSTNAME_S"
    printf 'fingerprint=%s\n' "$FP"
    printf 'os_family=%s\n' "$TE_OS_FAMILY"
    printf 'os_id=%s\n' "$TE_OS_ID"
    printf 'os_version=%s\n' "$TE_OS_VER"
    printf 'arch=%s\n' "$(uname -m 2>/dev/null || printf 'unknown')"
    printf 'item_total=%s\n' "$ITEM_TOTAL"
    printf 'item_success=%s\n' "$N_SUCCESS"
    printf 'item_skipped=%s\n' "$N_SKIPPED"
    printf 'item_failed=%s\n' "$N_FAILED"
    printf 'ps_version=\n'
    printf 'checksum_algorithm=sha256\n'
  } > "$OUT_DIR/MANIFEST.txt"
  (
    cd "$OUT_DIR" || exit 1
    for _c in MANIFEST.txt status.env logs/collect.log data/*; do
      [ -f "$_c" ] || continue
      _ch=$(sha256_file "$_c")
      [ -n "$_ch" ] || _ch=-
      printf '%s  %s\n' "$_ch" "$_c"
    done
  ) > "$OUT_DIR/CHECKSUMS.sha256"
  PKG_PATH="$OUT_DIR"
  PKG_SHA=''
  if have tar; then
    if (cd "$OUT_BASE" && tar czf "$PKG_NAME.tar.gz" "$PKG_NAME" 2>> "$COLLECT_LOG"); then
      PKG_PATH="$OUT_BASE/$PKG_NAME.tar.gz"
      PKG_SHA=$(sha256_file "$PKG_PATH")
    fi
  fi
  printf '\n'
  printf '=== EnvProbe collect summary ===\n'
  printf 'items: total=%s success=%s skipped=%s failed=%s\n' "$ITEM_TOTAL" "$N_SUCCESS" "$N_SKIPPED" "$N_FAILED"
  printf 'package: %s\n' "$PKG_PATH"
  if [ -n "$PKG_SHA" ]; then
    printf 'package sha256: %s\n' "$PKG_SHA"
  fi
  if [ "$PKG_PATH" = "$OUT_DIR" ]; then
    printf 'note: tar unavailable, package directory kept (archive it manually)\n'
  fi
  log 'envprobe done'
}

main "$@"

exit 0
