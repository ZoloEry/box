#!/system/bin/sh

# 变量定义
box_dir="/data/adb/box"
box_run="${box_dir}/run"
box_pid="${box_run}/box.pid"

run_as_su() {
    su -c "$1"
}

stop_service() {
    echo "服务正在关闭..."
    # 先停核心：TUN 设备、mihomo 自身的路由表与 ip rule 随进程退出一起消失，
    # 避免清理时核心仍在运行、规则被重新写入，造成“清了又出现”的错觉。
    run_as_su "${box_dir}/scripts/box.service stop"
    # 再清 box 自己下发的规则（旁路链、路由表、CNIP 等）
    run_as_su "${box_dir}/scripts/box.iptables disable"
}

start_service() {
    echo "服务正在启动，请稍候..."
    run_as_su "${box_dir}/scripts/box.service start"
    run_as_su "${box_dir}/scripts/box.iptables enable"
}

if [ -f "${box_pid}" ]; then
    PID=$(cat "${box_pid}")
    if [ -e "/proc/${PID}" ]; then
        stop_service
    else
        start_service
    fi
else
    start_service
fi
