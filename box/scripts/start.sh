#!/system/bin/sh

scripts_dir="${0%/*}"
file_settings="/data/adb/box/settings.ini"
moddir="/data/adb/modules/box_for_root"

if [ -f "$file_settings" ]; then
    . "$file_settings"
fi

# busybox Magisk/KSU/Apatch
busybox="/data/adb/magisk/busybox"
[ -f "/data/adb/ksu/bin/busybox" ] && busybox="/data/adb/ksu/bin/busybox"
[ -f "/data/adb/ap/bin/busybox" ] && busybox="/data/adb/ap/bin/busybox"

wait_for_data_ready() {
  while [ ! -f "/data/system/packages.xml" ] ; do
    sleep 1
  done
}

refresh_box() {
  if [ -f "/data/adb/box/run/box.pid" ]; then
    "${scripts_dir}/box.service" stop > "/dev/null" 2>&1 &
    "${scripts_dir}/box.iptables" disable > "/dev/null" 2>&1 &
    wait
  fi
}

start_service() {
  if [ -f "$file_settings" ]; then
    . "$file_settings"
  fi
  
  if [ "$boot_auto_start" = "false" ]; then
    log Info "开机自启已禁用，跳过启动核心服务。"
    return 0
  fi
  
  if [ ! -f "${moddir}/disable" ]; then
    "${scripts_dir}/box.service" start > "/dev/null" 2>&1
  fi
}

enable_iptables() {
  PIDS=("mihomo" "xray" "sing-box" "v2fly")
  PID=""
  i=0
  while [ -z "$PID" ] && [ "$i" -lt "${#PIDS[@]}" ]; do
    PID=$($busybox pidof "${PIDS[$i]}")
    i=$((i+1))
  done

  if [ -n "$PID" ]; then
    "${scripts_dir}/box.iptables" enable > "/dev/null" 2>&1
  fi
}

net_inotifyd() {
  while [ ! -f /data/misc/net/rt_tables ] ; do
    sleep 1
  done

  net_dir="/data/misc/net"
  # Use inotifyd to monitor write events in the /data/misc/net directory for network changes, perhaps we have a better choice of files to monitor (the /proc filesystem is unsupported) and cyclic polling is a bad solution
  inotifyd "${scripts_dir}/net.inotify" "${net_dir}" > "/dev/null" 2>&1 &
}

start_inotifyd() {
  PIDs=($($busybox pidof inotifyd))
  for PID in "${PIDs[@]}"; do
    if grep -q -e "box.inotify" -e "net.inotify" "/proc/$PID/cmdline"; then
      kill -9 "$PID"
    fi
    # if grep -q "box.inotify" "/proc/$PID/cmdline"; then
      # kill -9 "$PID"
    # fi
  done
  inotifyd "${scripts_dir}/box.inotify" "${moddir}" > "/dev/null" 2>&1 &
  net_inotifyd
}

mkdir -p /data/adb/box/run/ /data/adb/box/run/state/ >/dev/null 2>&1 || true
if [ -f "/data/adb/box/manual" ]; then
  if [ -f "/data/adb/box/run/box.pid" ]; then
      rm /data/adb/box/run/box.pid
  fi
  net_inotifyd
  exit 1
fi

if [ -f "$file_settings" ] && [ -r "$file_settings" ] && [ -s "$file_settings" ]; then
  wait_for_data_ready
  refresh_box
  # 启用网络服务控制时，先让监听做一次策略判断，再决定是否启动核心。
  # 否则连接黑名单 Wi-Fi 重启后会先启动核心、再被策略停止（issue #42）。
  if [ "${enable_network_service_control}" = "true" ] && [ -f "${scripts_dir}/ctr.utils" ]; then
    start_inotifyd
    busybox sleep 2
    "${scripts_dir}/net.inotify" w
  else
    start_service
    enable_iptables
    start_inotifyd
    # 开机后延迟做一次代理健康检查：开机时通常没有网络变化事件，
    # inotifyd 不会触发 net.inotify，核心若在开机时绑错接口就会一直
    # 节点全黑，直到手动重启。这里主动触发一次，让看门狗有机会自愈。
    ( ${busybox} sleep 75; "${scripts_dir}/net.inotify" w ) >/dev/null 2>&1 &
  fi
else
  start_inotifyd
fi
