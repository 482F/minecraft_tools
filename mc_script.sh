#!/bin/bash
#
# mincraft_server start/stop/backup script
#

set -ue -o pipefail
 
# minecraft_serverディレクトリ
SERVER_DIR=$(cd $(dirname "${0}"); pwd)

MC_DIR=$(dirname $(dirname "${SERVER_DIR}"))

# screen名
SCNAME=$(basename "${SERVER_DIR}")
 
SERVER_PROPERTIES="${SERVER_DIR}/server.properties"

# 実行するminecraft_server.jar
SERVICENAME="main.jar"
SERVICE="${SERVER_DIR}/${SERVICENAME}"

if [ ! -f "${SERVICE}" ]; then
    echo "there is no \"main.jar\""
    echo ""
    declare -a JARS=($(ls -1 "${SERVER_DIR}/*.jar"))
    NoJ="${#JARS[@]}"
    nl -w 3 <(echo "${JARS[@]}" | xargs -n1 echo)
    echo ""
    echo "select ln target"
    read TARGET_NUM
    if ! expr "${TARGET_NUM}" + 1 >&/dev/null || [ ${TARGET_NUM} -lt 1 ] || [ ${NoJ} -lt ${TARGET_NUM} ]; then
        echo "invalid target number"
        exit 1
    fi
    TARGET_NUM=$((TARGET_NUM-1))
    ln -s "${JARS[${TARGET_NUM}]}" "main.jar"
    exit 0
fi

# メモリ設定
XMX='1024M'
XMS='1024M'
 
## バックアップ用設定
# バックアップ格納ディレクトリ
BK_DIR="${MC_DIR}/backups/${SCNAME}"
 
# バックアップ取得時間
BK_TIME=`date +%Y%m%d-%H%M%S`
 
# 完全バックアップデータ名
FULL_BK_NAME="$BK_DIR/full_${BK_TIME}.tar.gz"
 
# 簡易パックアップデータ名
HOUR_BK_NAME="$BK_DIR/hourly_${BK_TIME}.tar"
 
# 簡易バックアップ対象データ
BK_FILE="$SERVER_DIR/world \
         $SERVER_DIR/banned-ips.json \
         $SERVER_DIR/banned-players.json \
         $SERVER_DIR/ops.json \
         $SERVER_DIR/server.properties \
         $SERVER_DIR/usercache.json \
         $SERVER_DIR/whitelist.json"
 
# バックアップデータ保存数
BK_GEN="3"
 
cd $SERVER_DIR
 
if [ ! -d $BK_DIR ]; then
    mkdir $BK_DIR
fi
 
ME=`whoami`

send_command_to_screen(){
    screen -p 0 -S "${SCNAME}" -X eval "stuff \"${1}\"\015"
    return 0
}

multi_line_echo(){
    for arg in "${@}"; do
        echo "${arg}"
    done
    return 0
}

start() {
    if pgrep -f "${SCNAME} java" > /dev/null; then
        echo "$SERVICE is already running!"
            exit 1
    fi
    echo "Starting $SERVICE..."
    screen -AmdS $SCNAME java -Xmx$XMX -Xms$XMS -jar $SERVICE nogui
}
 
stop() {
    if pgrep -f "${SCNAME} java" > /dev/null; then
        echo "Stopping $SERVICE"
        send_command_to_screen "say SERVER SHUTTING DOWN IN 3 SECONDS. Saving map..."
        send_command_to_screen "save-all"
        sleep 3
        send_command_to_screen "stop"
        sleep 10
        echo "Stopped minecraftserver"
    else
        echo "$SERVICE is not running!"
    fi
}

reload() {
    stop
    start
}
 
h_backup() {
    if pgrep -f $SERVICE > /dev/null; then
        echo "Backup start minecraft data..."
        send_command_to_screen "save-all"
        sleep 10
        send_command_to_screen "save-off"
        tar cfv $HOUR_BK_NAME $BK_FILE
        sleep 10
        send_command_to_screen "save-on"
        echo "minecraft_server backup compleate!"
        gzip -f $HOUR_BK_NAME
        find $BK_DIR -name "mc_backup_hourly_*.tar.gz" -type f -mtime +$BK_GEN -exec rm {} \;
    else
        echo "$SERVICE was not runnning."
    fi
}
 
f_backup() {
    if pgrep -f "${SERVICE}" > /dev/null; then
        echo "Full backup start minecraft data..."
        send_command_to_screen "say サーバーの再起動が約 10 秒後に行われます。"
        send_command_to_screen "save-all"
        sleep 10
        send_command_to_screen "stop"
        echo "Stopped minecraft_server"
        echo "Full Backup start ..."
        tar cfvz "${FULL_BK_NAME}" -C / "${SERVER_DIR#/}"
        sleep 10
        echo "Full Backup compleate!"
        find "${BK_DIR}" -name "mc_backup_full*.tar.gz" -type f -mtime +$BK_GEN -exec rm {} \;
        echo "Starting ${SERVICE}..."
        screen -AmdS ${SCNAME} java -Xmx$XMX -Xms$XMS -jar ${SERVICE} nogui
    else
        echo "$SERVICE was not runnning."
    fi
}

enable_backup(){
    (crontab -l; echo "0 12 * * * ${SERVER_DIR}/mc_script.sh backup full") | crontab -
}

disable_backup(){
    CRONCONF=$(crontab -l)
    CRONCONF=$(sed -e "s@0 12 \* \* \* ${SERVER_DIR}/mc_script.sh backup full@@g" <(echo "${CRONCONF}"))
    (echo "${CRONCONF}") | crontab -
}

status_full() {
    sudo monit status "${SCNAME}"
    status
}
 
status() {
    if pgrep -f $SERVICE > /dev/null; then
        echo "running"
        exit 0
    else
        echo "not running"
        exit 0
    fi
}

get_motd() {
    cat server.properties | grep -e "^motd" | python3.5 -c 'from sys import stdin; import codecs; print(codecs.decode(stdin.readline(), "unicode-escape"))'
}

set_motd() {
    NEW_MOTD=$(echo $@ | python3.5 -c 'from sys import stdin; print(str(stdin.readline().encode("unicode-escape"))[2:-4])' | sed -e s@\\\\\\\\\\\\\\\\n@\\\\\\\\n@)
    perl -pi -e "s|(?<=^motd\=).*|${NEW_MOTD}|" "${SERVER_PROPERTIES}"
}

monit(){
    sudo monit "${@}" "${SCNAME}"
}

add_monit() {
    echo "check process \"${SCNAME}\" matching \"SCREEN -AmdS ${SCNAME} java*\"" | sudo tee "/etc/monit.d/${SCNAME}.conf" > /dev/null
    echo '    not every "0-10 12 * * *"' | sudo tee -a "/etc/monit.d/${SCNAME}.conf" > /dev/null
    echo "    start program = \"/usr/bin/sudo -u normal ${SERVER_DIR}/mc_script.sh start"\" | sudo tee -a "/etc/monit.d/${SCNAME}.conf" > /dev/null
    echo "    stop program = \"/usr/bin/sudo -u normal ${SERVER_DIR}/mc_script.sh stop"\" | sudo tee -a "/etc/monit.d/${SCNAME}.conf" > /dev/null
    echo "    if 3 restarts within 3 cycles then timeout" | sudo tee -a "/etc/monit.d/${SCNAME}.conf" > /dev/null
    sudo monit reload
}

remove_monit(){
    sudo rm "/etc/monit.d/${SCNAME}.conf"
    sudo monit reload
}

screen_attach(){
    screen -r "${SCNAME}"
    return 0
}

port_set(){
    local PC=$(port_check)
    port_close
    perl -pi -e "s|(?<=^server-port\=).*|${1}|" "${SERVER_PROPERTIES}"
    if [ -z "{PC:-}" ]; then
        port_open
    fi
    return 0
}

port_get(){
    cat "${SERVER_PROPERTIES}" | grep "server-port" | sed -e "s@^server-port\=@@g"
    return 0
}

port_open(){
    if [ ! -f "${SERVER_DIR}/allowed_ip_list.txt" ]; then
        echo "${SERVER_DIR}/allowed_ip_list.txt does not exist."
        exit 1
    fi
    port_close
    local PORT="$(port_get)"
    local IPTABLES="$(sudo cat "/etc/sysconfig/iptables")"
    if ! echo "${IPTABLES}" | grep -qE "^# minecraft$"; then
        local -a FILTER_LINE_NUM="$(echo "${IPTABLES}" | grep -nE "^\*filter$" | sed -e "s/:.*//g")"
        local -a COMMIT_LINE_NUMS=($(echo "${IPTABLES}" | grep -nE "^COMMIT$" | sed -e "s/:.*//g"))
        for COMMIT_LINE_NUM in "${COMMIT_LINE_NUMS[@]}"; do
            if [ ${FILTER_LINE_NUM} -lt ${COMMIT_LINE_NUM} ]; then
                break
            fi
        done
        IPTABLES="$(echo "${IPTABLES}" | sed -e "${COMMIT_LINE_NUM}i #dummy_line\n# minecraft\n" | sed -e "s/#dummy_line//g")"
    fi
    local ins_line="$(echo "${IPTABLES}" | grep -nE "^# minecraft$" | sed -e "s/:.*//g")"
    IPTABLES="$(echo "${IPTABLES}" | sed -e "${ins_line}a # ${SCNAME}\n")"
    ins_line=$((ins_line+1))
    for ip in $(cat "${SERVER_DIR}/allowed_ip_list.txt"); do
        IPTABLES="$(echo "${IPTABLES}" | sed -e "${ins_line}a -A INPUT -s ${ip}/32 -p tcp -m state --state NEW -m tcp --dport ${PORT} -j ACCEPT")"
    done
    echo "${IPTABLES}" | sudo tee "/etc/sysconfig/iptables" > /dev/null
    sudo service iptables reload
    return 0
}

port_close(){
    local PORT="$(port_get)"
    local IPTABLES="$(sudo cat "/etc/sysconfig/iptables")"
    echo "${IPTABLES}" |
    sed -e "/# ${SCNAME}/d" |
    sed -e "/-A INPUT -s .*\/32 -p tcp -m state --state NEW -m tcp --dport ${PORT} -j ACCEPT/d" |
    sudo tee "/etc/sysconfig/iptables" > /dev/null
    sudo service iptables reload
    return 0
}

port_check(){
    local PORT="$(port_get)"
    sudo grep "^-A INPUT -s .*\/32 -p tcp -m state --state NEW -m tcp --dport ${PORT} -j ACCEPT$" /etc/sysconfig/iptables |
    grep -oE "([0-9]{1,3}\.){3}[0-9]"
    return 0
}

kick(){
    send_command_to_screen "kick ${1}"
    return 0
}

usage(){
    case "${1:-}" in
    start)
        multi_line_echo "${0} start"\
        "    start minecraft server"
        ;;
    stop)
        multi_line_echo "${0} stop"\
        "    stop minecraft server"
        ;;
    reload)
        multi_line_echo "${0} reload"\
        "    stop and start minecraft server"
        ;;
    status)
        multi_line_echo "${0} status"\
        "    show status of minecraft server and monit status"
        ;;
    backup)
        case "${2:-}" in
        half)
            multi_line_echo "${0} backup half"\
            ""\
            "    backup a part of minecraft server's data"
            ;;
        full)
            multi_line_echo "${0} backup full"\
            ""\
            "    backup all minecraft server's data"
            ;;
        enable)
            multi_line_echo "${0} backup enable"\
            ""\
            "    enable full backup everyday 12:00 by cron"
            ;;
        disable)
            multi_line_echo "${0} backup disable"\
            ""\
            "    disable full backup everyday 12:00 by cron"
            ;;
        *)
            multi_line_echo "${0} backup subcommand"\
            ""\
            "subcommand:"\
            "    half"\
            "    full"\
            "    enable"\
            "    disable"
            ;;
        esac
        ;;
    monit)
        case "${2:-}" in
        add)
            multi_line_echo "${0} monit add"\
            ""\
            "    make conf file in /etc/monit.d/ and reload monit"
            ;;
        remove)
            multi_line_echo "${0} monit remove"\
            ""\
            "    remove conf file in /etc/monit.d/ and reload monit"
            ;;
        *)
            multi_line_echo "${0} monit subcommand"\
            ""\
            "subcommand:"\
            "    add"\
            "    remove"\
            "    monit command"\
            "        ex) ${0} monit {status|monitor|unmonitor...}"
            ;;
        esac
        ;;
    motd)
        case "${2:-}" in
        get)
            multi_line_echo "${0} motd get"\
            ""\
            "    print motd in server.properties (description which is displaied in server list)"
            ;;
        set)
            multi_line_echo "${0} motd set"\
            ""\
            "    set motd STRING in server.properties (description which is displaied in server list)"
            ;;
        *)
            multi_line_echo "${0} motd subcommand"\
            ""\
            "subcommand:"\
            "    get"\
            "    set STRING"
            ;;
        esac
        ;;
    screen)
        case "${2:-}" in
        attach)
            multi_line_echo "${0} screen attach"\
            ""\
            "    attach minecraft server's screen session"
            ;;
        *)
            multi_line_echo "${0} screen subcommand"\
            ""\
            "subcommand:"\
            "    attach"
        esac
        ;;
    port)
        case "${2:-}" in
        get)
            multi_line_echo "${0} port get"\
            ""\
            "    get server's port"
            ;;
        set)
            multi_line_echo "${0} port set PORTNUM"\
            ""\
            "    set server's port PORTNUM and change setting of iptables"
            ;;
        open)
            multi_line_echo "${0} port open"\
            ""\
            "    open server's port by iptables according to allowed_ip_list.txt"
            ;;
        close)
            multi_line_echo "${0} port close"\
            ""\
            "    close server's port by iptables"
            ;;
        check)
            multi_line_echo "${0} port check"\
            ""\
            "    show which ip address are allowed to access"
            ;;
        *)
            multi_line_echo "${0} port subcommand"\
            ""\
            "subcommand:"\
            "    set"\
            "    get"\
            "    open"\
            "    close"\
            "    check"
        esac
        ;;
    kick)
        multi_line_echo "${0} kick username"
        ;;
    *)
        multi_line_echo "${0} arguments"\
        ""\
        "arguments:"\
        "    start"\
        "    stop"\
        "    reload"\
        "    status"\
        "    backup subcommand"\
        "    monit subcommand"\
        "    motd subcommand"\
        "    screen subcommand"\
        "    port subcommand"
        ;;
    esac
    return 0
}

if [ -z "${1:-}" ] || [ "--help" = "${@:$#:1}" ] || [ "-h" = "${@:$#:1}" ]; then
    usage "${@}"
    exit 0
fi

case "${1}" in
start)
    start
    ;;
stop)
    stop
    ;;
reload)
    reload
    ;;
status)
    status
    ;;
backup)
    case "${2:-}" in
    half)
        h_backup
        ;;
    full)
        f_backup
        ;;
    enable)
        enable_backup
        ;;
    disable)
        disable_backup
        ;;
    *)
        usage backup
        exit 1
    esac
    ;;
monit)
    case "${2:-}" in
    add)
        add_monit
        ;;
    remove)
        remove_monit
        ;;
    *)
        shift
        monit "${@}"
    esac
    ;;
motd)
    case "${2:-}" in
    set)
        set_motd "${3}"
        ;;
    get)
        get_motd
        ;;
    *)
        usage motd
        exit 1
    esac
    ;;
screen)
    case "${2:-}" in
    attach)
        screen -r "${SCNAME}"
        ;;
    *)
        usage screen
        exit 1
    esac
    ;;
port)
    case "${2:-}" in
    set)
        port_set "${3:-}"
        ;;
    get)
        port_get
        ;;
    open)
        port_open
        ;;
    close)
        port_close
        ;;
    check)
        port_check
        ;;
    *)
        usage port
        exit 1
    esac
    ;;
kick)
    kick "${2:-}"
    ;;
*)
    usage
    exit 1
esac
