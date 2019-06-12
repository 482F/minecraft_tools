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
        screen -p 0 -S $SCNAME -X eval 'stuff "say SERVER SHUTTING DOWN IN 3 SECONDS. Saving map..."\015'
        screen -p 0 -S $SCNAME -X eval 'stuff "save-all"\015'
        sleep 3
        screen -p 0 -S $SCNAME -X eval 'stuff "stop"\015'
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
        screen -p 0 -S $SCNAME -X eval 'stuff "save-all"\015'
        sleep 10
        screen -p 0 -S $SCNAME -X eval 'stuff "save-off"\015'
        tar cfv $HOUR_BK_NAME $BK_FILE
        sleep 10
        screen -p 0 -S $SCNAME -X eval 'stuff "save-on"\015'
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
        screen -p 0 -S $SCNAME -X eval 'stuff "say サーバーの再起動が約 10 秒後に行われます。"\015'
        screen -p 0 -S $SCNAME -X eval 'stuff "save-all"\015'
        sleep 10
        screen -p 0 -S $SCNAME -X eval 'stuff "stop"\015'
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

case "$1" in
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
get_motd)
    get_motd
    ;;
set_motd)
    set_motd "$2"
    ;;
*)
    echo  $"Usage: $0 {start|stop|reload|h_backup|f_backup|status|(get|set)_motd}"
esac
