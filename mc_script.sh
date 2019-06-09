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
BK_DIR="${MC_DIR}/backups/${SERVICENAME}"
 
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
    if pgrep -f $SERVICE > /dev/null; then
        echo "Full backup start minecraft data..."
        send_command_to_screen "say サーバーの再起動が約 10 秒後に行われます。"
        send_command_to_screen "save-all"
        sleep 10
        send_command_to_screen "stop"
        echo "Stopped minecraft_server"
        echo "Full Backup start ..."
        screen -ls
        tar cfvz $FULL_BK_NAME $SERVER_DIR
        sleep 10
        echo "Full Backup compleate!"
        find $BK_DIR -name "mc_backup_full*.tar.gz" -type f -mtime +$BK_GEN -exec rm {} \;
        echo "Starting $SERVICE..."
        screen -AmdS $SCNAME java -Xmx$XMX -Xms$XMS -jar $SERVICE nogui
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
 
status() {
    sudo monit status "${SCNAME}"
    if pgrep -f $SERVICE > /dev/null; then
        echo "$SERVICE is already running!"
        exit 0
    else
        echo "$SERVICE is not running!"
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

remove_monit() {
    sudo rm "/etc/monit.d/${SCNAME}.conf"
    sudo monit reload
}

usage(){
    if [ "" = "${1:-}" ]; then
        usage "-h"
        return 0
    fi
    case "${1}" in
    start)
        echo "${0} start"
        echo "    start minecraft server"
        ;;
    stop)
        echo "${0} stop"
        echo "    stop minecraft server"
        ;;
    reload)
        echo "${0} reload"
        echo "    stop and start minecraft server"
        ;;
    status)
        echo "${0} status"
        echo "    show status of minecraft server and monit status"
        ;;
    backup)
        if [ "" = "${2:-}" ]; then
            echo "${0} backup subcommand"
            echo ""
            echo "subcommand:"
            echo "    half"
            echo "    full"
            echo "    enable"
            echo "    disable"
        else
            case "${2}" in
            half)
                echo "${0} backup half"
                echo ""
                echo "    backup a part of minecraft server's data"
                ;;
            full)
                echo "${0} backup full"
                echo ""
                echo "    backup all minecraft server's data"
                ;;
            enable)
                echo "${0} backup enable"
                echo ""
                echo "    enable full backup everyday 12:00 by cron"
                ;;
            disable)
                echo "${0} backup disable"
                echo ""
                echo "    disable full backup everyday 12:00 by cron"
                ;;
            *)
                usage backup
                ;;
            esac
        fi
        ;;
    monit)
        if [ "" = "${2:-}" ]; then
            echo "${0} monit subcommand"
            echo ""
            echo "subcommand:"
            echo "    add"
            echo "    remove"
            echo "    monit command"
            echo "        ex) ${0} monit {status|monitor|unmonitor...}"
        else
            case "${2}" in
            add)
                echo "${0} monit add"
                echo ""
                echo "    make conf file in /etc/monit.d/ and reload monit"
                ;;
            remove)
                echo "${0} monit remove"
                echo ""
                echo "    remove conf file in /etc/monit.d/ and reload monit"
                ;;
            *)
                usage monit
                ;;
            esac
        fi
        ;;
    motd)
        if [ "" = "${2:-}" ]; then
            echo "${0} motd subcommand"
            echo ""
            echo "subcommand:"
            echo "    get"
            echo "    set STRING"
        else
            case "${2}" in
            get)
                echo "${0} motd get"
                echo ""
                echo "    print motd in server.properties (description which is displaied in server list)"
                ;;
            set)
                echo "${0} motd set"
                echo ""
                echo "    set motd STRING in server.properties (description which is displaied in server list)"
                ;;
            *)
                usage motd
                ;;
            esac
        fi
        ;;
    *)
        echo "${0} arguments"
        echo ""
        echo "arguments:"
        echo "    start"
        echo "    stop"
        echo "    reload"
        echo "    status"
        echo "    backup subcommand"
        echo "    monit subcommand"
        echo "    motd subcommand"
        ;;
    esac
    return 0
}

if [ "" = "${@:-}" ] || [ "--help" = "${@:$#:1}" ] || [ "-h" = "${@:$#:1}" ]; then
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
    case "${2}" in
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
        exit 1
    esac
    ;;
monit)
    case "${2}" in
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
    case "${2}" in
    set)
        set_motd "${3}"
        ;;
    get)
        get_motd
        ;;
    *)
        exit 1
    esac
    ;;
*)
    usage
    exit 1
esac
