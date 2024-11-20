#!/bin/bash
ex() {((ex_var++)); [[ "$ex_var" == 1 ]] && configure_imgdir clear; echo $'\e[m'; exit; }
trap ex INT

# Запуск:               sh='PVE-ASDaC-BASH.sh';curl -sOLH 'Cache-Control: no-cache' "https://raw.githubusercontent.com/PavelAF/PVE-ASDaC-BASH/main/$sh"&&chmod +x $sh&&./$sh;rm -f $sh

echo $'\nProxmox VE Automatic stand deployment and configuration script by AF\n'

############################# -= Конфигурация =- #############################

# Необходимые команды для работы на скрипта
script_requirements_cmd=( curl qm pvesh pvesm pveum qemu-img qemu-kvm md5sum )

# Приоритет параметров: значения в этом файле -> значения из импортированного файла конфигурации -> переопределенные значения из аргуметов командной строки

# Переменные со значениями по-умолчанию:
# _name - описание, name - значение

declare -A config_base=(
    [_inet_bridge]='Интерфейс с выходом в Интернет, NAT и DHCP'
    [inet_bridge]='{auto}'

    [_start_vmid]='Начальный идентификатор ВМ (VMID), с коротого будут создаваться ВМ'
    [start_vmid]='{auto}'

    [_mk_tmpfs_imgdir]='Временный раздел tmpfs в ОЗУ для хранения образов ВМ (уничтожается в конце установки)'
    [mk_tmpfs_imgdir]='/root/ASDaC_TMPFS_IMGDIR'

    [_storage]='Имя хранилища для для развертывания ВМ'
    [storage]='{auto}'

    [_pool_name]='Шаблон имени пула стенда'
    [_def_pool_name]='Шаблон имени пула стенда по умолчанию'
    [def_pool_name]='PROF39_stand_{0}'

    [_pool_desc]='Шаблон описания пула стенда'
    [pool_desc]='Стенд участника демэкзамена "Сетевое и системное администрирование". Стенд #{0}'

    [_take_snapshots]='Создавать снапшоты ВМ (снимки, для сброса стендов)'
    [take_snapshots]=true

    [_access_create]='Создавать пользователей, группы, роли для разграничения доступа'
    [access_create]=true

    [_access_user_name]='Шаблон имени пользователя стенда'
    [_def_access_user_name]='Шаблон имени пользователя стенда по умолчанию'
    [def_access_user_name]='Competitor{0}'

    [_access_user_desc]='Описание пользователя участника'
    [access_user_desc]='Учетная запись участика демэкзамена #{0}'

    [_access_user_enable]='Включить учетные записи участиков сразу после развертывания стендов'
    [access_user_enable]=true

    [_access_pass_length]='Длина создаваемых паролей для пользователей'
    [access_pass_length]=5

    [_access_pass_chars]='Используемые символы в паролях [regex]'
    [access_pass_chars]='A-Z0-9'

    [_access_auth_pam_desc]='Изменение отображаемого названия аутентификации PAM'
    [access_auth_pam_desc]='System'

    [_access_auth_pve_desc]='Изменение отображаемого названия аутентификации PVE'
    [access_auth_pve_desc]='Аутентификация участника'
)

_config_access_roles='Список ролей прав доступа'
declare -A config_access_roles=(
    [Competitor]='Pool.Audit VM.Audit VM.Console VM.PowerMgmt VM.Snapshot.Rollback VM.Config.Network'
    [Competitor_ISP]='VM.Audit VM.Console VM.PowerMgmt VM.Snapshot.Rollback'
)

# Конфигурация шаблонов для создаваемых виртуальных машин. Особые параметры:
# network{X} - список именованных сетей (сети (bridge vmbr) создаются автоматически)
# возможна подстановка: заключается в скобки { }
# внешний интерфейс vmbr: {bridge=inet}
# добавить выключеный интерфейс: {bridge="link_down", state=down}
# добавить другой существующий в системе vmbr: {bridge=[vmbr0]}
# в подстанонвочных объявлениях интерфейса {bridge="iface_{0}"} возможа подстановка номера стенда
# boot_disk0 - файл виртуального boot диска ВМ. возможные значения: file, yadisk_url, url
# может быть несколько, boot_disk1, boot_disk2 и т.д.
# disk1, disk2 ... - дополнительно создаваемые диски ( размер в Гб. прим: 1, 0.1 и т.д.). если у диска должно быть конкретноне заполнение, можно указать файл образа диска, так же, как в boot_disk
# access_roles - список ролей (прав) доступа участника к ВМ (через пробел: role1 role2)
# disk_type - тип виртуального "железа" для диска для ВМ [ide|scsi|virtio|sata]
# netifs_type - тип виртуального "железа" сетевого интерфейса для ВМ
# config_template - импорт настроек ВМ из ранее описанного шаблона
_config_templates='Список шаблонов ВМ'
declare -A config_templates=(
    [_Alt-Server_10.1]='Базовый шаблон для Alt Server 10.1'
    [Alt-Server_10.1]='
        tags = alt_server
        ostype = l26
        serial0 = socket
        agent = 1
        scsihw = virtio-scsi-single
        cpu = host
        cores = 1
        memory = 1536
        boot_disk0 = https://disk.yandex.ru/d/31yfM0_qNhTTkw/Alt-Server_10.1.qcow2
        access_roles = Competitor
    '
    [_Alt-Workstation_10.1]='Базовый шаблон для Alt-Workstation 10.1'
    [Alt-Workstation_10.1]='
        tags = alt_workstation
        ostype = l26
        serial0 = socket
        agent = 1
        scsihw = virtio-scsi-single
        cpu = host
        cores = 2
        memory = 2048
        boot_disk0 = https://disk.yandex.ru/d/31yfM0_qNhTTkw/Alt-Workstation_10.1.qcow2
        access_roles = Competitor
    '
    [_Eltex-vESR]='Базовый шаблон для vESR'
    [Eltex-vESR]='
        tags = eltex-vesr
        ostype = l26
        serial0 = socket
        agent = 0
        acpi = 0
        scsihw = virtio-scsi-single
        cpu = host
        cores = 4
        memory = 3072
        netifs_type = e1000
        boot_disk0 = https://disk.yandex.ru/d/31yfM0_qNhTTkw/vESR.qcow2
        access_roles = Competitor
    '
    [_EcoRouter]='Базовый шаблон для EcoRouter'
    [EcoRouter]='
        tags = ecorouter
        ostype = l26
        machine = pc-i440fx-8.0
        serial0 = socket
        agent = 0
        acpi = 1
        cpu = host
        cores = 2
        memory = 4096
        rng0 = source=/dev/urandom
        disk_type = ide
        netifs_type = e1000
        network0 = { bridge="mgmt_net{0}", state=down }
        boot_disk0 = https://disk.yandex.ru/d/31yfM0_qNhTTkw/EcoRouter.qcow2
        access_roles = Competitor
    '
)

_config_stand_1_var='Вариант стенда демэкзамена 09.02.06-1-2024. ОС: Alt Server, Alt Workstation, Eltex vESR'
declare -A config_stand_1_var=(
    [_stand_config]='
        pool_name = DE_09.02.06-2024_stand_{0}
        stands_display_desc = Стенды демэкзамена 09.02.06 Сетевое и системное администрирование
        pool_desc = Стенд участника демэкзамена "Сетевое и системное администрирование". Стенд #{0}
        access_user_name = Student{0}
        access_user_desc = Учетная запись участика демэкзамена #{0}
    '

    [_ISP]='Alt Server 10.1'
    [ISP]='
        config_template = Alt-Server_10.1
        startup = order=1,up=8,down=30
        network1 = {bridge=inet}
        network2 = 🖧: ISP<=>HQ-R
        network3 = 🖧: ISP<=>BR-R
    '
    [_CLI]='Alt Workstation 10.1'
    [CLI]='
        config_template = Alt-Workstation_10.1
        startup = order=3,up=8,down=30
        network1 = {bridge=inet}
        network2 = 🖧: CLI<=>HQ-R
    '
    [_HQ-R]='Eltex vESR'
    [HQ-R]='
        config_template = Eltex-vESR
        startup = order=2,up=8,down=60
        network1 = 🖧: ISP<=>HQ-R
        network2 = 🖧: HQ-R<=>HQ-SRV
        network3 = 🖧: CLI<=>HQ-R
    '
    [_HQ-SRV]='Alt Server 10.1'
    [HQ-SRV]='
        config_template = Alt-Server_10.1
        startup = order=3,up=8,down=60
        network1 = 🖧: HQ-R<=>HQ-SRV
    '
    [_BR-R]='Eltex vESR'
    [BR-R]='
        config_template = Eltex-vESR
        startup = order=2,up=8,down=60
        network1 = 🖧: ISP<=>BR-R
        network2 = 🖧: BR-R<=>BR-SRV
    '
    [_BR-SRV]='Alt Server 10.1'
    [BR-SRV]='
        config_template = Alt-Server_10.1
        startup = order=3,up=8,down=60
        network1 = 🖧: BR-R<=>BR-SRV
        disk0 = 1GB
        disk1 = 1GB
        disk2 = 1GB
    '
)

_config_stand_2_var='Вариант стенда демэкзамена 09.02.06-1-2024. ОС: Alt Server, Alt Workstation'
declare -A config_stand_2_var=(
    [_stand_config]='
        pool_name = DE_09.02.06-2024_stand_{0}
        stands_display_desc = Стенды демэкзамена 09.02.06 Сетевое и системное администрирование
        pool_desc = Стенд участника демэкзамена "Сетевое и системное администрирование". Стенд #{0}
        access_user_name = Student{0}
        access_user_desc = Учетная запись участика демэкзамена #{0}
    '

    [_ISP]='Alt Server 10.1'
    [ISP]='
        config_template = Alt-Server_10.1
        startup = order=1,up=8,down=30
        network1 = {bridge=inet}
        network2 = 🖧: ISP<=>HQ-R
        network3 = 🖧: ISP<=>BR-R

    '
    [_CLI]='Alt Workstation 10.1'
    [CLI]='
        config_template = Alt-Workstation_10.1
        startup = order=3,up=8,down=30
        network1 = {bridge=inet}
        network2 = 🖧: CLI<=>HQ-R
    '
    [_HQ-R]='Alt Server 10.1'
    [HQ-R]='
        config_template = Alt-Server_10.1
        startup = order=2,up=8,down=60
        network1 = 🖧: ISP<=>HQ-R
        network2 = 🖧: HQ-R<=>HQ-SRV
        network3 = 🖧: CLI<=>HQ-R
    '
    [_HQ-SRV]='Alt Server 10.1'
    [HQ-SRV]='
        config_template = Alt-Server_10.1
        startup = order=3,up=8,down=60
        network1 = 🖧: HQ-R<=>HQ-SRV
    '
    [_BR-R]='Alt Server 10.1'
    [BR-R]='
        config_template = Alt-Server_10.1
        startup = order=2,up=8,down=60
        network1 = 🖧: ISP<=>BR-R
        network2 = 🖧: BR-R<=>BR-SRV
    '
    [_BR-SRV]='Alt Server 10.1'
    [BR-SRV]='
        config_template = Alt-Server_10.1
        startup = order=3,up=8,down=60
        network1 = 🖧: BR-R<=>BR-SRV
        disk0 = 1GB
        disk1 = 1GB
        disk2 = 1GB
    '
)

########################## -= Конец конфигурации =- ##########################





# Объявление вспомогательных функций:

c_black=$'\e[0;30m'
c_lblack=$'\e[1;30m'
c_red=$'\e[0;31m'
c_lred=$'\e[1;31m'
c_green=$'\e[0;32m'
c_lgreen=$'\e[1;32m'
c_yellow=$'\e[0;33m'
c_lyellow=$'\e[1;33m'
c_blue=$'\e[0;34m'
c_lblue=$'\e[1;34m'
c_purple=$'\e[0;35m'
c_lpurple=$'\e[1;35m'
c_cyan=$'\e[0;36m'
c_lcyan=$'\e[1;36m'
c_gray=$'\e[0;37m'
c_white=$'\e[1;37m'

c_null=$'\e[m'
c_value=$c_lblue
c_error=$c_lred
c_warning=$c_lpurple
c_info=$c_purple
c_ok=$c_green

function get_val_print() {
    [[ "$1" == true ]] && echo "$c_greenДа$c_null" && return 0
    [[ "$1" == false ]] && echo "$c_redНет$c_null" && return 0
    if [[ "$2" == storage ]] && ! [[ "$1" =~ ^\{(manual|auto)\}$ ]] && [[ "$sel_storage_space" != '' ]]; then
        echo "$c_value$1$c_null (свободно $(echo "$sel_storage_space" | awk 'BEGIN{ split("К|М|Г|Т",x,"|") } { for(i=1;$1>=1024&&i<length(x);i++) $1/=1024; print int($1) " " x[i] "Б" }'))"
        return 0
    elif [[ "$2" == access_pass_chars ]]; then
        echo "[$c_value$1$c_null]"
        return 0
    fi
    echo "$c_value$1$c_null"
}

function echo_err() {
    echo "$c_error$@$c_null" >/dev/tty
}

function echo_warn() {
    echo "$c_warning$@$c_null" >/dev/tty
}

function read_question_select() {
    local read; until read -p "$1: $c_value" read; echo -n $c_null >/dev/tty
        [[ "$2" == '' || $(echo "$read" | grep -Pc "$2" ) == 1 ]] && { ! isdigit_check "$read" || [[ "$3" == '' || "$read" -ge "$3" ]] && [[ "$4" == '' || "$read" -le "$4" ]]; }
    do true; done; echo "$read";
}

function read_question() { local read; until read -n 1 -p "$1 [y|д|1]: $c_value" read; echo $c_null >/dev/tty; [[ "$read" =~ [yд1l] ]] && return 0 || [[ "$read" != '' ]] && return 1; do true; done; }

function get_numrange_array() {
    local IFS=,; set -- $1
    for range; do
        case $range in
            *-*) for (( i=${range%-*}; i<=${range#*-}; i++ )); do echo $i; done ;;
            *\.\.*) for (( i=${range%..*}; i<=${range#*..}; i++ )); do echo $i; done ;;
            *)   echo $range ;;
        esac
    done
}

function isbool_check() {
    [[ "$1" == 'true' || "$1" == 'false' ]] && return 0
    [[ ${!1} != '' ]] && {
        local -n isbool="$1"
        [[ "$isbool" =~ ^(true?|1|[yY](|[eE][sS]?)|[дД][аА]?)$ ]] && isbool=true && return 0
        [[ "$isbool" =~ ^(false?|0|[nN][oO]?|[нН](|[еЕ][тТ]?))$ ]] && isbool=false && return 0
    }
    return 1
}

function isdigit_check() {
    [[ "$1" =~ ^[0-9]+$ ]] || return 1
    [[ "$2" =~ ^[0-9]+$ ]] && { [[ "$1" -ge "$2" ]] || return 1; }
    [[ "$3" =~ ^[0-9]+$ ]] && { [[ "$1" -le "$3" ]] || return 1; }
    return 0
}

function isregex_check() {
    [[ "$(echo -n "$1" | wc -m)" -gt 255 ]] && return 1
    [[ $( echo | grep -Psq "$1" 2>/dev/null; echo $? ) == 1 ]] && return 0 || return 1
}

function isdict_var_check() {
    #[[ "${!1}" != '' ]] && set -- "${!1}"; [[ "${!1}" != '' ]] && set -- "${!1}"; [[ "${!1}" != '' ]] && set -- "${!1}"
    [[ $(eval echo "\${#$1[@]}") -gt 0 && "$(declare -p -- "$1")" == "declare -A "* ]] && return 0 || return 1
}

function invert_bool() {
  [[ "$1" == false ]] && echo true || echo false
}

function parse_noborder_table() {
    [[ "$1" == '' || "$2" == '' ]] && echo exit
    local _cmd="$1 --output-format text --noborder"
    local -n ref_dict_table=$2
    shift && shift
    local _table=$(eval "$_cmd") || { echo "Ошибка: не удалось выполнить команду $_cmd"; exit 1; }

    local _index=0 _header='' _name='' _column='' i=0
    while [[ "$(echo $_table)" != '' ]]; do
        _header=$(echo "$_table" | sed -n '1p')
        _index=$(echo "$_header" | grep -Pio '^[a-z\_]+\ *' | wc -m)
        [[ "$_index" == 0 ]] && break
        _name=$(echo "$_header" | grep -Pio '^[a-z\_]+')
        if echo "$_header" | grep -Piq '^[a-z\_]+(?=\ +[a-z\_])';
        then
            ((_index-=2))
            _column=$( echo -n "$_table" | sed -n '1!p' | grep -Po '^.{'$_index'}' | sed 's/ *$//'; echo -n "x")
            _column="${_column::-2}"
            _table=$( echo -n "$_table" | sed 's/^.\{'$((++_index))'\}//'; echo -n "x")
            _table="${_table::-1}"
        else
            _column=$( echo -n "$_table" | sed -n '1!p' | sed 's/ *$//'; echo -n "x")
            _column="${_column::-1}"
            _table=''
        fi
        [[ $# != 0 ]] && { printf '%s\n' $@ | grep -Fxq -- "$_name" || continue; }

        if [[ $# == 0 || $# -gt 1 ]]; then
            ref_dict_table["$_name"]=$_column || exit 1;
        else
            ref_dict_table=$_column || exit 1; return 0
        fi
    done
}

# Объявление осовных функций

function show_help() {
    local t=$'\t'
    echo 'Скрипт простого, быстрого развертывания/управления учебными стендами виртуальной ИТ инфраструктуры на базе гипервизора Proxmox VE'
    echo 'Базовые настройки можно изменять при запуске скрипта в основном (интерактивном режиме), так и через аргументы командной строки'
    echo 'Переменные конфигурации можно изменять в самом файле скрипта в разделе "Конфигурация"'
    echo 'Так же можно создать свой файл конфигурации и подгружать с помощью аргумента -c <file>'
    echo $'\nАргументы командной строки:'
    cat <<- EOL | column -t -s "$t"
        -h, --help$t$_opt_show_help
        -sh, --show-config <out-file>$t$_opt_show_config
        -v, --verbose$t$_opt_verbose
        --dry-run$t$_opt_dry_run
        -n, --stand-num [string]$t$_opt_stand_nums
        -var, --set-var-num [int]$t$_opt_sel_var
        -st, --storage [string]$t${config_base[_storage]}
        -vmid, --start-vm-id [integer]$t${config_base[_start_vmid]}
        -vmbr, --wan-bridge [string]$t${config_base[_inet_bridge]}
        -snap, --take-snapshots [boolean]$t${config_base[_take_snapshots]}
        -dir, --mk-tmpfs-dir [boolean]$t${config_base[_mk_tmpfs_imgdir]}
        -norm, --no-clear-tmpfs$t$_opt_rm_tmpfs
        -pn, --pool-name [string]$t${config_base[_pool_name]}
        -acl, --access-create [boolean]$t${config_base[_access_create]}
        -u, --user-name [string]$t${config_base[_access_user_name]}
        -l, --pass-length [integer]$t${config_base[_access_pass_length]}
        -char, --pass-chars [string]$t${config_base[_access_pass_chars]}
        -si, --silent-install$t$_opt_silent_install
        -c, --config [in-file]$tИмпорт конфигурации из файла или URL
        -z, --clear-vmconfig$t$_opt_zero_vms
        -sctl, --silent-control$t$_opt_silent_control
EOL
}


function show_config() {
    local i=0
    [[ "$1" != opt_verbose ]] && echo
    [[ "$1" == install-change ]] && {
            echo $'Список параметров конфигурации:\n  0. Выйти из режима изменения дополнительных настроек'
            for var in pool_name pool_desc storage inet_bridge take_snapshots access_create $( ${config_base[access_create]} && echo access_{user_{name,desc,enable},pass_{length,chars},auth_{pve,pam}_desc} ); do
                echo "  $((++i)). ${config_base[_$var]:-$var}: $( get_val_print "${config_base[$var]}" "$var" )"
            done
            echo "  $((++i)). $_opt_dry_run: $( get_val_print $opt_dry_run )"
            return 0
    }
    [[ "$1" == passwd-change ]] && {
            echo $'Список параметров конфигурации:\n  0. Запустить установку паролей пользователей'
            for var in access_pass_{length,chars}; do
                echo "  $((++i)). ${config_base[_$var]:-$var}: $( get_val_print "${config_base[$var]}" "$var" )"
            done
            return 0
    }
    if [[ "$1" == detailed || "$1" == verbose ]]; then
        local description=''
        local value=''
        echo '#>---------------------- Параметры конфигурации -----------------------<#'
        [[ "$1" == detailed ]] && echo '#>-------------- Эта конфигурация создана автоматически ---------------<#'

        for conf in $(compgen -v | grep -P '^config_(base|access_roles|templates|stand_[1-9][0-9]{0,3}_var)$' | awk '{if(NR>1)printf " ";printf $0}'); do
            description="$(eval echo "\$_$conf")"
            [[ "$description" != "" && "$1" == detailed ]] && \
                if [[ ! "$conf" =~ ^config_stand_[1-9][0-9]{0,3}_var$ ]]; then echo -e "\n# $description"
                else echo -e "\n_$conf='$description'"; fi
            for var in $(eval echo "\${!$conf[@]}"); do
                [[ "$var" =~ ^_ ]] && continue
                #[[ "$var" =~ ^_(?!stand_config) ]] && continue
                description="$(eval echo "\${$conf[_$var]}")"
                [[ "$description" != "" && "$1" == detailed ]] && \
                    if [[ ! "$conf" =~ ^config_(stand_[1-9][0-9]{0,3}_var|templates)$ ]]; then echo -e "\n# $description"
                    else echo -e "\n$conf["_$var"]='$description'"; fi
                value=$(IFS= eval echo "\${$conf[$var]}" | awk 'NF>0{ $1=$1;print "\t"$0}')
                if [[ $(echo -n "$value" | grep -c '^') == 1 ]]; then
                    value="$(sed -e 's/^\s*//;s/\s*$//' <<<${value})"
                    echo -e "$conf["$var"]='\e[1;34m${value}\e[m'"
                else
                    echo -e "$conf["$var"]='\n\e[1;34m${value}\e[m\n'"
                fi
            done
        done
        echo '#<------------------- Конец параметров конфигурации ------------------->#'
    else
        if [[ "$1" != var ]]; then
            echo $'#>------------------ Осовные параметры конфигурации -------------------<#\n'
            for var in inet_bridge storage take_snapshots access_create; do
                echo "$((++i)). ${config_base[_$var]:-$var}: $(get_val_print "${config_base[$var]}" "$var" )"
            done

            if ${config_base[access_create]}; then
                for var in $( [[ "${config_base[access_user_name]}" == '' ]] && echo def_access_user_name || echo access_user_name ) access_user_enable access_pass_length access_pass_chars; do
                    echo "$((++i)). ${config_base[_$var]:-$var}: $(get_val_print "${config_base[$var]}" "$var" )"
                done
            fi
        fi
        i=1
        local first_elem=true
        local no_elem=true
        local pool_name=''
        if [[ $opt_sel_var != 0 ]]; then
            i=$opt_sel_var
            echo $'\nВыбранный вариант установки стендов:'
            local vars="config_stand_${opt_sel_var}_var"
        else
            echo $'\nВарианты установки стендов:'
            local vars=$(compgen -v | grep -P '^config_stand_[1-9][0-9]{0,3}_var$' | awk '{if (NR>1) printf " ";printf $0}')
        fi
        for conf in $vars; do
            description="$(eval echo "\$_$conf")"
            [[ "$description" == "" ]] && description="Вариант $i (без названия)"
            get_dict_value "$conf[_stand_config]" pool_name=pool_name
            [[ "$pool_name" != "" ]] && description="$pool_name : $description"
            for var in $(eval echo "\${!$conf[@]}"); do
                [[ "$var" =~ ^_ ]] && continue
                $first_elem && first_elem=false && echo -n $'\n  '"$((i++)). $description"$'\n  - ВМ: '
                no_elem=false
                description="$(eval echo "\${$conf[_$var]}")"
                echo -en "$var"
                [[ "$description" != "" ]] && echo -en "(\e[1;34m${description}\e[m) " || echo -n ' '
            done
            ! $first_elem && echo
            first_elem=true
        done
        $no_elem && echo '--- пусто ---'

        if [[ "${#opt_stand_nums[@]}" != 0 && "$1" != var && "$opt_sel_var" != 0 ]]; then
            echo -n $'\n'"Номера стендов: $c_value"
            printf '%s\n' "${opt_stand_nums[@]}" | awk 'BEGIN{d="-"}NR==1{first=$1;last=$1;next} $1 == last+1 {last=$1;next} {d="-";if (first==last-1)d=",";printf first d last",";first=$1;last=first} END{if (first==last-1)d=",";if (first!=last)printf first d; printf last"\n"}'
            echo -n "$c_null"
            echo "Всего стендов к развертыванию: $(get_val_print "${#opt_stand_nums[@]}" )"
            echo "Кол-во создаваемых виртуальных машин: $(get_val_print "$(( ${#opt_stand_nums[@]} * $(eval "printf '%s\n' \${!config_stand_${opt_sel_var}_var[@]}" | grep -Pv '^_' | wc -l) ))" )"
        fi
    fi
    [[ "$1" != opt_verbose ]] && echo
}

function del_vmconfig() {
    for conf in $(compgen -v | grep -P '^_?config_stand_[1-9][0-9]{0,3}_var$' | awk '{if (NR>1) printf " ";printf $0}'); do
        unset $conf
    done
}

function isurl_check() {
    [[ "$2" != "yadisk" ]] && local other_proto='?|ftp'
    [[ $(echo "$1" | grep -Pc '(*UCP)\A(https'$other_proto')://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]\Z' ) == 1 ]] && return 0
    return 1
}

function yadisk_url() {
    local -n ref_url="$1"
    isurl_check "$ref_url" yadisk || { echo_err "Ошибка yadisk_url: указанный URL '$ref_url' не является валидным. Выход"; exit 1; }
    [[ "$1" =~ ^https\://disk\.yandex\.ru/i/ ]] && { echo_err "Ошибка yadisk_url: указанный URL ЯДиска '$ref_url' не является валидным, т.к. файл защищен паролем. Скачивание файлов ЯДиска защищенные паролем на даный момент недоступно. Выход"; exit 1; }
    local path=`echo "$ref_url" | grep -Po '.*/d/[^/]*/\K.*'`
    local regex='\A[\s\n]*{([^{]*?|({[^}]*}))*\"{opt_name}\"\s*:\s*((\"\K[^\"]*)|\K[0-9]+)'
    local opt_name='type'
    local reply="$( curl --silent -G 'https://cloud-api.yandex.net/v1/disk/public/resources?public_key='$(echo "$ref_url" | grep -Po '.*/[di]/[^/]*')'&path=/'$path )"
    [[ "$( echo "$reply" | grep -Poz "${regex/\{opt_name\}/"$opt_name"}" | sed 's/\x0//g' )" != file ]] && { echo_err "Ошибка: публичная ссылка '$ref_url' не ведет на файл. Попробуйте указать прямую ссылку (включая подпапки), проверьте URL или обратитесь к системному администратору"; exit 1; }
    shift
    opt_name='file'
    ref_url="$(echo "$reply" | grep -Poz "${regex/\{opt_name\}/$opt_name}" | sed 's/\x0//g')"
    while [[ "$1" != '' ]]; do
        [[ "$1" =~ ^[a-zA-Z][0-9a-zA-Z_]{0,32}\=(name|size|antivirus_status|mime_type|sha256|md5)$ ]] || { echo_err "Ошибка yadisk_url: некорректый аргумент '$1'"; exit 1; }
        opt_name="${1#*=}"
        local -n ref_var="${1%=*}"
        ref_var="$( echo "$reply" | grep -Poz "${regex/\{opt_name\}/"$opt_name"}" | sed 's/\x0//g' )"
        [[ "$ref_var" == '' ]] && { echo_err "Ошибка yadisk_url: API Я.Диска не вернуло запрашиваемое значение '$opt_name'"; exit 1; }
        shift
    done
}

function get_url_filesize() {
    isurl_check "$1" || { echo_err "Ошибка get_url_filesize: указанный URL '$1' не является валидным. Выход"; exit 1; }
    local return=$( curl -s -L -I "$1" | grep -Poi '^Content-Length: \K[0-9]+(?=\s*$)' )
}
#TODO
function get_url_filename() {
    isurl_check "$1" || { echo_err "Ошибка get_url_filename: указанный URL '$1' не является валидным. Выход"; exit 1; }
    local return=$( curl -L --head -w '%{url_effective}' "$1" 2>/dev/null | tail -n1 )
}

function get_file() {

    [[ "$1" == '' ]] && exit 1

    local -n url="$1"
    local md5=$(echo $url | md5sum)
    md5="h${md5::-3}"

    [[ -v list_img_files["$md5"] && -r "${list_url_files[$md5]}" ]] && url="${list_url_files[$md5]}" && return 0


    local max_filesize=${2:-5368709120}
    local filesize=''
    local filename=''
    isdigit_check "$max_filesize" || { echo_err "Ошибка get_file max_filesize=$max_filesize не число" && exit 1; }
    local force=$( [[ "$3" == force ]] && echo true || echo false )

    if [[ "$url" =~ ^https://disk\.yandex\.ru/ ]]; then
        yadisk_url url filesize=size filename=name
    elif isurl_check "$url"; then
        filesize=$(get_url_filesize $url)
        filename=$(get_url_filename $url)
    fi
    if isurl_check "$url"; then
        isdigit_check $filesize && [[ "$filesize" -gt 0 ]] && maxfilesize=$filesize
        if [[ "$filename" == '' ]]; then
            filename="$(mktemp 'ASDaC_noname_downloaded_file.XXXXXXXXXX' -p "${config_base[mk_tmpfs_imgdir]}")"
        else
            filename="${config_base[mk_tmpfs_imgdir]}/$filename"
        fi
        if [[ $filesize -gt $max_filesize ]]; then
            if $force && [[ "$filesize" -le $(($filesize+4194304)) ]]; then
                echo_warn "Предупреждение: загружаемый файл $filename больше разрешенного значения: $((filesize/1024/1024/1024)) ГБ"
                max_filesize=$(($filesize+4194304))
            else
                echo_err 'Ошибка: загружаемый файл больше разрешенного размера или сервер отправил ответ о неверном размере файла'
                exit 1
            fi
        fi
        [[ -r "$filename" ]] || {
            configure_imgdir add-size $max_filesize
            curl --max-filesize $max_filesize -GL "$url" -o "$filename" || { echo_err "Ошибка скачивания. Выход"; exit 1; }
            # | iconv -f windows-1251 -t utf-8 > $tempfile
        }
    fi
    [[ -r "$filename" ]] || { echo_err "Ошибка: файл '$filename' должен существовать и быть доступен для чтения"; exit 1; }
    url="$filename"
    list_url_files["$md5"]="$url"
}

function set_configfile() {

    $opt_zero_vms && del_vmconfig && opt_zero_vms=false

    local file="$1"
    local error=false
    get_file file 655360

    if [[ "$( file -bi "$file" )" == 'text/plain; charset=utf-8' ]]; then
        source <( sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2};?)?)?[mGK]//g;s/\r//g" "$file" \
            | grep -Pzo '(\R|^)\s*config_(((access_roles|templates)\[_?[a-zA-Z][a-zA-Z0-9\_\-\.]+\])|(base\[('$( printf '%q\n' "${!config_base[@]}" | grep -Pv '^_' | awk '{if (NR>1) printf "|";printf $0}' )')\]))=(([^\ "'\'']|\\["'\''\ ])*|(['\''][^'\'']*['\'']))(?=\s*($|\R))' | sed 's/\x0//g') \
        || { echo_err 'Ошибка при импорте файла конфигурации. Выход'; exit 1; }

        start_var=$(compgen -v | grep -Po '^config_stand_\K[1-9][0-9]{0,3}(?=_var$)' | awk 'BEGIN{max=0}{if ($1>max) max=$1}END{print max}')

        source <(
            i=$start_var
            arr=()
            sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2};?)?)?[mGK]//g;s/\r//g" "$file" \
                | grep -Pzo '(\R|^)\s*_?config_stand_[1-9][0-9]{0,3}_var(\[([\w\d]+(|(\.|-+)(?=[\w\d])))+\]|)='\''[^'\'']*'\''(?=\s*($|\R))' \
                | sed 's/\x0//g' | cat - <(echo) \
                | while IFS= read -r line; do
                if [[ "$line" =~ ((\R|^)_?config_stand_)([1-9][0-9]*)(.*) ]]; then
                    num=${BASH_REMATCH[3]}
                    [[ ! ${arr[num]+1} ]] && arr[num]=$((++i)) && echo "declare -A -g config_stand_${i}_var";
                    echo "${BASH_REMATCH[1]}${arr[num]}${BASH_REMATCH[4]}"
                else echo "$line"
                fi
                done
        )
    else
        echo_err 'Ошибка: файл должен иметь тип "file=text/plain; charset=utf-8"'
        exit 1
    fi
    echo
}

function set_standnum() {
    if [[ $( echo "$1" | grep -P '\A^([0-9]{1,3}((\-|\.\.)[0-9]{1,3})?([\,](?!$\Z)|(?![0-9])))+$\Z' -c ) != 1 ]]; then
        echo_err 'Ошибка - неверный ввод: номера стендов. Выход'; exit 1
    fi
    local tmparr=( $( get_numrange_array "$1") )
    while IFS= read -r -d '' x; do opt_stand_nums+=("$x"); done < <(printf "%s\0" "${tmparr[@]}" | sort -nuz)
}

function configure_standnum() {
    [[ ${#opt_stand_nums} -ge 1 ]] && return 0
    $silent_mode && [[ ${#opt_stand_nums} == 0 ]] && echo_err 'Ошибка: не указаны номера стендов для развертывания. Выход' && exit 1
    [[ "$is_show_config" == 'false' ]] && { is_show_config=true; show_config; }
    echo $'\nВведите номера инсталляций стендов. Напр., 1-5 развернет стенды под номерами 1, 2, 3, 4, 5 (всего 5)'
    set_standnum $( read_question_select 'Номера стендов (прим: 1,2,5-10)' '^([0-9]{1,3}((\-|\.\.)[0-9]{1,3})?([\,](?!$\Z)|(?![0-9])))+$' )
}

function set_varnum() {
    isdigit_check "$1" && [[ "$1" -ge 1 ]] && isdict_var_check "config_stand_$1_var" && opt_sel_var=$1 && return 0
    echo_err 'Ошибка: номер варианта развертки должен быть числом и больше 0 и такой вариант должен существовать. Возможна некорректная конфигурация этого вариантаразвертывания. Выход' && exit 1
}

function configure_varnum() {
    [[ $opt_sel_var -ge 1 ]] && return 0
    $silent_mode && [[ $opt_sel_var == 0 ]] && echo_err 'Ошибка: не указан выбор варианта развертывания. Выход' && exit 1
    [[ "$is_show_config" == 'false' ]] && { is_show_config=true; show_config var; }
    local count=$(compgen -v | grep -P '^config_stand_[1-9][0-9]{0,3}_var$' | wc -l)
    local var=0
    if [[ $count -gt 1 ]]; then
        var=$( read_question_select 'Вариант развертывания стендов' '^[0-9]+$' 1 $(compgen -v | grep -P '^config_stand_[1-9][0-9]{0,3}_var$' | wc -l) )
    else var=1
    fi
    set_varnum $var
    echo -n "Выбранный вариант инсталляции - ${var}: "
    get_val_print "$(eval echo "\$_config_stand_${var}_var")"
}

function configure_wan_vmbr() {
    [[ "$1" == 'check-only' ]] && [[ "${config_base[inet_bridge]}" == '{manual}' || "${config_base[inet_bridge]}" == '{auto}' ]] && return 0
    [[ "$is_show_config" == 'false' ]] && { is_show_config=true; show_config; }

    local ipr4=$( ip -4 route |& grep -Po '^[\.0-9\/]+\ dev\ [\w\.]+' )
    local ipr6=$( ip -6 route |& grep -Po '^(?!fe([89ab][0-9a-f]))[0-9a-f\:\/]+\ dev\ [\w\.]+' )
    local default4=$( ip -4 route get 1 |& grep -Po '\ dev\ \K[\w]+' )
    local default6=$( ip -6 route get 1::1 |& grep -Po '\ dev\ \K[\w]+(?=\ |$)' )

    local bridge_ifs='' all_bridge_ifs=''
    command -v ovs-vsctl >/dev/null && bridge_ifs=$( ovs-vsctl list-br 2>/dev/null )$'\n'
    bridge_ifs+=$( ip link show type bridge up | grep -Po '^[0-9]+:\ \K[\w\.]+' )
    bridge_ifs=$( echo "$bridge_ifs" | sort )
    all_bridge_ifs="$bridge_ifs"
    echo "$bridge_ifs" | grep -Fxq "$default4" || default4=''
    echo "$bridge_ifs" | grep -Fxq "$default6" || default6=''
    local list_links_master=$( (ip link show up) | grep -Po '^[0-9]+:\ \K.*\ master\ [\w\.]+' )

    local i iface ip4 ip6 slave_ifs slave next=false
    for ((i=1;i<=$(echo -n "$bridge_ifs" | grep -c '^');i++)); do
            iface=$( echo "$bridge_ifs" | sed -n "${i}p" )
        echo "$iface" | grep -Pq '^('$default4'|'$default6')$' && {
            bridge_ifs=$( echo "$bridge_ifs" | sed -n "${i}!p" ); (( i > 0 ? i-- : i )); continue;
        }
        ip4=$( echo "$ipr4" | grep -Po '^[\.0-9\/]+(?=\ dev\ '$iface')' )
        ip6=$( echo "$ipr6" | grep -Po '^[0-9a-f\:\/]+(?=\ dev\ '$iface'(?=\ |$))' )
        [[ "$ip4" != '' || "$ip6" != '' ]] && continue;
        slave_ifs=$( echo "$list_links_master" | grep -Po '^[\w\.]+(?=.*?\ master\ '$iface'(\ |$))' )
        next=false
        while [[ "$(echo -n "$slave_ifs" | grep -c '^')" != 0 ]]; do
            slave=$( echo "$slave_ifs" | sed -n "1p" )
            echo "$all_bridge_ifs" | grep -Fxq "$slave" || { next=true; break; }
            slave_ifs=$( echo "$slave_ifs" | sed -n "1!p" )
            slave_ifs+=$( echo; echo "$list_links_master" | grep -Po '^[\w\.]+(?=.*?\ master\ '$slave'(\ |$))' )
            slave_ifs=$( echo "$slave_ifs" | sed '/^$/d' )
        done
        ! $next && bridge_ifs=$( echo "$bridge_ifs" | sed -n "${i}!p" ) && (( i > 0 ? i-- : i ))
    done
    bridge_ifs=$( (echo "$bridge_ifs"; echo "$default6"; echo "$default4") | sed '/^$/d' )

    set_vmbr_menu() {
        local if_count=$(echo -n "$bridge_ifs" | grep -c '^')
        local if_all_count=$(echo -n "$all_bridge_ifs" | grep -c '^')
        [[ "$if_count" == 0 ]] && {
            [[ "$if_all_count" == 0 ]] && echo_err "Ошибка: не найдено ни одного активного bridge интерфейса в системе. Выход" && exit 1
            bridge_ifs="$all_bridge_ifs"
            if_count=$(echo -n "$bridge_ifs" | grep -c '^')
        }
        echo $'\nУкажите bridge (vmbr) интерфейс в качестве вешнего интерфейса для ВМ:'
        for ((i=1;i<=$if_count;i++)); do
            iface=$( echo "$bridge_ifs" | sed -n "${i}p" )
            ip4=$( echo "$ipr4" | grep -Po '^[\.0-9\/]+(?=\ dev\ '$iface')' )
            ip6=$( echo "$ipr6" | grep -Po '^[0-9a-f\:\/]+(?=\ dev\ '$iface'(?=\ |$))' )
            echo "  ${i}. $c_value$iface$c_null IPv4='$c_value$ip4$c_null' IPv6='$c_value$ip6$c_null' slaves='$c_value"$( echo "$list_links_master" | grep -Po '^[\w\.]+(?=.*?\ master\ '$iface'(\ |$))' )"$c_null'"
        done
        local switch=$( read_question_select $'\nВыберите номер сетевого интерфейса' '' 1 $( echo -n "$bridge_ifs" | grep -c '^' ) )
        config_base[inet_bridge]=$( echo "$bridge_ifs" | awk -v n="$switch" 'NR == n')
        echo "$c_lgreenПодождите, идет проверка конфигурации...$c_null"
        return 0;
    }
    local check="$(echo "$all_bridge_ifs" | grep -Fxq "${config_base[inet_bridge]}" && echo true || echo false )"
    [[ "$1" == check-only && ! $check ]] && echo_warn 'Проверка конфигурации: в конфигурации внешний bridge (vmbr) интерфейс указан вручую и он неверный' && return
    if [[ ! $check || "$1" == manual ]]; then
        config_base[inet_bridge]='{manual}'
        if $silent_mode; then
            echo_warn $'Предупреждение: внеший интерфейс vmbr будет установлен автоматически, т.к. он указан неверно или {manual}.\nНажмите Ctrl-C, чтобы прервать установку'; sleep 10;
            config_base[inet_bridge]='{auto}'
        fi
    fi
    [[ $(echo -n "$bridge_ifs" | grep -c '^') == 1 ]] && config_base[inet_bridge]=$(echo "$bridge_ifs" | sed -n 1p ) && echo "Информация: внешний vmbr интерфейс установлен автоматически на значение \"${config_base[inet_bridge]}\", т.к. на хостовой машине это был единственный внешний bridge интерфейс" && return
    [[ $(echo -n "$all_bridge_ifs" | grep -c '^') == 1 ]] && config_base[inet_bridge]=$(echo "$all_bridge_ifs" | sed -n 1p ) && echo "Информация: внешний vmbr интерфейс установлен автоматически на значение \"${config_base[inet_bridge]}\", т.к. на хостовой машине это был единственный bridge интерфейс" && return

    [[ $(echo -n "$all_bridge_ifs" | grep -c '^') == 0 ]] && echo_err "Ошибка: не найдено ни одного активного Linux|OVS bridge сетевого интерфейса в системе. Выход" && exit 1

    case "${config_base[inet_bridge]}" in
        \{manual\}) set_vmbr_menu;;
        \{auto\})
            [[ "$default6" != '' ]] && config_base[inet_bridge]="$default6" && return 0
            [[ "$default4" != '' ]] && config_base[inet_bridge]="$default4" && return 0
            $silent_mode && echo_err 'Ошибка: не удалось автоматически определить внешний vmbr интерфейс. Установите его вручную. Выход' && exit
            set_vmbr_menu
            ;;
    esac
}

function configure_vmid() {
    [[ ${config_base[start_vmid]} =~ ^[0-9]+$ ]] && ! [[ ${config_base[start_vmid]} -ge 100 && ${config_base[start_vmid]} -le 10000 ]] && \
        echo_err 'Ошибка: указанный vmid вне диапазона разрешенных для использования'
    [[ "$1" == check-only ]] && return 0
    set_vmid() {
        [[ "$is_show_config" == 'false' ]] && { is_show_config=true; show_config; }
        config_base[start_vmid]=$(read_question_select $'Укажите начальный идентификатор ВМ (VMID), с коротого будут создаваться ВМ (100-999999000)' '^[0-9]+$' 100 999999000 )
    }
    local -a vmidlist vmbrlist
    IFS=' ' read -r -a vmidlist <<< "$(qm list | awk 'NR>1{print $1}' | sort -n)"
    vmbrcount="$(ip -br l | grep -oP '^vmbr\K[0-9]+' | grep -c '^' )"
    local -A intervalsId=()
    local i=100 id=0 count=0
    [[ "$1" == manual ]] && config_base[start_vmid]='{manual}'
    if [[ "${config_base[start_vmid]}" == '{auto}' ]] || [[ $silent_mode && "${config_base[start_vmid]}" == '{manual}' ]]; then
        config_base[start_vmid]=1000
    fi
    [[ "${config_base[start_vmid]}" == '{manual}' ]] && set_vmid
    vmidlist+=(999999999)
    count=$((${#opt_stand_nums[@]}*100))
    i=${config_base[start_vmid]}
    while [[ $i -lt ${vmidlist[-1]} ]]; do
        [[ "${vmidlist[$id]}" -gt $i && $((${vmidlist[$id]} - $i - 100)) -ge $count ]] && break
        [[ $i -gt 999999000 ]] && echo_err 'Ошибка: невозможно найти свободные VMID для развертывания стендов. Выход' && exit 1
        [[ "${vmidlist[$id]}" -gt $i ]] && i=$((${vmidlist[$id]}+1))
        ((id++))
    done
    config_base[start_vmid]=$((i % 2 * 100 + i - i % 100))

    count=$(( ${#opt_stand_nums[@]} * $(eval "printf '%s\n' \${!config_stand_${opt_sel_var}_var[@]}" | grep -Pv '^_' | wc -l) ))

    [[ $((11100 - vmbrcount - count)) -le 0 ]] && echo_err 'Ошибка: невозможно найти свободные номера bridge vmbr-интерфейсов для создания сетей для стендов' && exit 1
}

function configure_imgdir() {
    [[ ${#config_base[mk_tmpfs_imgdir]} -lt 1 && ${#config_base[mk_tmpfs_imgdir]} -ge 255 ]] && echo_err 'Ошибка: путь временой директории некоректен (2-255): ${#config_base[mk_tmpfs_imgdir]}. Выход' && exit 1

    [[ "$1" == clear ]] && {
        { ! $opt_rm_tmpfs || $opt_not_tmpfs; } && return 0
        [[ $(findmnt -T "${config_base[mk_tmpfs_imgdir]}" -o FSTYPE -t tmpfs | wc -l) != 1 ]] && {
            echo
            $silent_mode || read_question "Удалить временный раздел со скачанными образами ВМ ('${config_base[mk_tmpfs_imgdir]}')?" \
                && { umount "${config_base[mk_tmpfs_imgdir]}"; rmdir "${config_base[mk_tmpfs_imgdir]}"; }
        }
        return 0
    }

    if [[ "$1" == check-only ]]; then
        awk '/MemAvailable/ {if($2<8388608) {exit 1} }' /proc/meminfo || \
            { echo_err $'Ошибка: Недостаточно свободной оперативной памяти!\nДля развертывания стенда необходимо как минимум 16 ГБ свободоной ОЗУ'; exit 1; }
        return 0
    fi

    [[ $(findmnt -T "${config_base[mk_tmpfs_imgdir]}" -o FSTYPE -t tmpfs | wc -l) != 1 ]] \
        && mkdir -p "${config_base[mk_tmpfs_imgdir]}" && \
            { mountpoint -q "${config_base[mk_tmpfs_imgdir]}" || mount -t tmpfs tmpfs "${config_base[mk_tmpfs_imgdir]}" -o size=1M; } \
            || { echo_err 'Ошибка при создании временного хранилища tmpfs'; exit 1; }

    if [[ "$1" == add-size ]]; then
        isdigit_check "$2" || { echo "Ошибка: " && exit 1; }
        awk -v size=$((($2+8388608)/1024)) '/MemAvailable/ {if($2<size) {exit 1} }' /proc/meminfo || \
            { echo_err $'Ошибка: Недостаточно свободной оперативной памяти!\nДля развертывания стенда необходимо как минимум '$((size/1024/1024))' ГБ свободоной ОЗУ'; exit 1; }
        local size="$( df | awk -v dev="${config_base[mk_tmpfs_imgdir]}" '$6==dev{print $3}' )"
        isdigit_check "$size" || { echo "Ошибка: 1 \$size=$size" && exit 1; }
        size=$((size*1024+$2+4294967296))
        mount -o remount,size=$size "${config_base[mk_tmpfs_imgdir]}" || { echo_err "Ошибка: не удалось расширить временный tmpfs раздел. Выход"; exit 1; }
    fi
}

function check_name() {
    local -n ref_var="$1"

    if [[ "$ref_var" =~ ^[\-0-9a-zA-Z\_\.]+(\{0\})?[\-0-9a-zA-Z\_\.]*$ ]] \
        && [[ "$(echo -n "$ref_var" | wc -m)" -ge 3 && "$(echo -n "$ref_var" | wc -m)" -le 32 ]]; then
        [[ ! "$ref_var" =~ \{0\} ]] && ref_var+='{0}'
        return 0
    else
        return 1
    fi
}

function configure_poolname() {
    [[ "$1" == check-only && "${config_base[pool_name]}" == '' && "$opt_sel_var" == 0 ]] && return
    local def_value=${config_base[pool_name]}
    [[ "$opt_sel_var" != 0 && "${config_base[pool_name]}" == '' ]] && {
        get_dict_value "config_stand_${opt_sel_var}_var[_stand_config]" config_base[pool_name]=pool_name
        [[ "${config_base[pool_name]}" == '' ]] && config_base[pool_name]=${config_base[def_pool_name]}
        $silent_mode && [[ "${config_base[pool_name]}" == '' ]] && echo_err "Ошибка: не удалось установить имя пула. Выход" && exit 1
    }
    [[ "$1" == 'set' ]] && {
        echo 'Введите шаблон имени PVE пула стенда. Прим: DE_stand_training_{0}'
        config_base[pool_name]=$( read_question_select 'Шаблон имени пула' '^[\-0-9a-zA-Z\_\.]*(\{0\})?[\-0-9a-zA-Z\_\.]*$' )
        shift
    }
    check_name 'config_base[pool_name]' ||  { echo_err "Ошибка: шаблон имён пулов некорректный: '${config_base[pool_name]}'. Запрещенные символы или длина больше 32 или меньше 3. Выход"; ${3:-true} && exit 1 || config_base[pool_name]=$def_value && return 1; }

    [[ "$1" == 'install' ]] && {
        local pool_list pool_name
            parse_noborder_table 'pveum pool list' pool_list poolid
        for stand in ${opt_stand_nums[@]}; do
            pool_name="${config_base[pool_name]/\{0\}/$stand}"
            echo "$pool_list" | grep -Fxq -- "$pool_name" \
                && { echo_err "Ошибка: пул '$pool_name' уже существует!"; ${3:-true} && exit 1 || config_base[pool_name]=$def_value && return 1; }
        done
    }
}

function configure_username() {
    [[ "$1" == check-only && "${config_base[access_user_name]}" == '' && "$opt_sel_var" == 0 ]] && return 0
    local def_value=${config_base[access_user_name]}
    [[ "$opt_sel_var" != 0 && "${config_base[access_user_name]}" == '' ]] && {
        get_dict_value "config_stand_${opt_sel_var}_var[_stand_config]" 'config_base[access_user_name]=access_user_name'
        [[ "${config_base[access_user_name]}" == '' ]] && config_base[access_user_name]=${config_base[def_access_user_name]}
        $silent_mode && [[ "${config_base[access_user_name]}" == '' ]] && echo "Ошибка: не удалось установить имя пула. Выход" && exit 1
    }
    [[ "$1" == 'set' ]] && {
        echo 'Введите шаблон имени пользователя стенда. Прим: Student{0}'
        config_base[access_user_name]=$( read_question_select 'Шаблон имени пользователя' '^[\-0-9a-zA-Z\_\.]*(\{0\})?[\-0-9a-zA-Z\_\.]*$' )
        shift
    }
    check_name 'config_base[access_user_name]' ||  { echo_err "Ошибка: шаблон имён пользователей некорректный: '${config_base[access_user_name]}'. Запрещенные символы или длина больше 32 или меньше 3. Выход"; ${3:-true} && exit 1 || config_base[access_user_name]=$def_value && return 1; }

    if [[ "$1" == 'install' ]] && ${config_base[access_create]} || [[ "$1" == 'set-install' ]]; then
        local user_list user_name
            parse_noborder_table 'pveum user list' user_list userid
        for stand in ${opt_stand_nums[@]}; do
            user_name="${config_base[access_user_name]/\{0\}/$stand}@pve"
            echo "$user_list" | grep -Fxq -- "$user_name" \
                && { echo_err "Ошибка: пользователь $user_name уже существует!"; ${3:-true} && exit 1 || config_base[access_user_name]=$def_value && return 1; }
        done
    fi
    return 0
}

function descr_string_check() {
    [[ "$( echo -n "$1" | wc -m )" -le 200 ]] && return 0 || return 1
}


function configure_storage() {
    [[ "$1" == check-only ]] && [[ "${config_base[storage]}" == '{auto}' || "${config_base[storage]}" == '{manual}' ]] && return 0
    set_storage() {
            echo $'\nСписок доступных хранилищ:'
            echo "$pve_storage_list" | awk -F' ' 'BEGIN{split("К|М|Г|Т",x,"|")}{for(i=1;$2>=1024&&i<length(x);i++)$2/=1024;print NR"\t"$1"\t"$3"\t"int($2)" "x[i]"Б"; }' \
            | column -t -s$'\t' -N'Номер,Имя хранилища,Тип хранилища,Свободное место' -o$'\t' -R1
            config_base[storage]=$( read_question_select 'Выберите номер хранилища'  '^[1-9][0-9]*$' 1 $(echo -n "$pve_storage_list" | grep -c '^') )
            config_base[storage]=$(echo "$pve_storage_list" | awk -F' ' -v nr="${config_base[storage]}" 'NR==nr{print $1}')
    }
    pve_storage_list=$( pvesm status  --target "$(hostname)" --enabled 1 --content images | awk -F' ' 'NR>1{print $1" "$6" "$2}' | sort -k2nr )
    [[ "$pve_storage_list" == '' ]] && echo_err 'Ошибка: подходящих хранилищ не найдено' && exit 1

    if [[ "$1" != check-only ]]; then
        if [[ "${config_base[storage]}" == '{manual}' ]]; then
            $silent_mode && config_base[storage]='{auto}' || set_storage
        fi
        [[ "${config_base[storage]}" == '{auto}' ]] && config_base[storage]=$(echo "$pve_storage_list" | awk 'NR==1{print $1;exit}')

    fi

    if ! [[ "${config_base[storage]}" =~ ^\{(auto|manual)\}$ ]]; then
        echo "$pve_storage_list" | awk -v s="${config_base[storage]}" 'BEGIN{e=0}$1==s{e=1;exit e}END{exit e}' && echo_err "Ошибка: выбранное имя хранилища \"${config_base[storage]}\" не существует. Выход" && exit 1

        sel_storage_type=$( echo "$pve_storage_list" | awk -v s="${config_base[storage]}" '$1==s{print $3;exit}' )
        sel_storage_space=$( echo "$pve_storage_list" | awk -v s="${config_base[storage]}" '$1==s{print $2;exit}' )

        case $sel_storage_type in
            dir|glusterfs|cifs|nfs|btrfs) config_disk_format=qcow2;;
            rbd|iscsidirect|iscsi|zfs|zfspool|lvmthin|lvm) config_disk_format=raw;;
            *) echo_err "Ошибка: тип хранилища '$sel_storage_type' неизвестен. Ошибка скрипта или более новая версия PVE? Выход"; exit 1;;
        esac
    fi
}

_configure_roles='проверка валидности списка access ролей (привилегий) Proxmox-а'
function configure_roles() {

    local list_privs=$( pvesh get /access/permissions --output-format yaml --path / --userid root@pam | grep -Po '^\s*\K[a-zA-Z\.]+(?=\:\ 1$)' ) \
        || { echo_err "Ошибка: get не удалось загрузить список привилегий пользователей"; exit 1; }
    [[ "$(echo -n "$list_privs" | grep -c '^')" -ge 20 ]] || { echo_err "Ошибка: не удалось корректно загрузить список привилегий пользователей"; exit 1; }

    for role in ${!config_access_roles[@]}; do
        ! [[ "$role" =~ ^[a-zA-Z\_][\-a-zA-Z\_]*$ && "$(echo -n "$role" | wc -m)" -le 32 ]] && echo_err "Ошибка: имя роли '$role' некорректное. Выход" && exit 1
        config_access_roles["$role"]=$( echo "${config_access_roles[$role]}" | sed 's/,\| /\n/g;s/\n\n//g' | sort )
        for priv in ${config_access_roles[$role]}; do
            printf '%s\n' "$list_privs" | grep -Fxq -- "$priv" && continue || {
                echo_err "Ошибка: название привилегии '$priv' в роли '$role' некорректа. Выход"
                exit 1
            }
        done
        config_access_roles["$role"]=$( echo -n "${config_access_roles[$role]}" | tr '\n' ','  )
    done
}

function check_config() {
    [[ "$1" == '' ]] && set -- check-only
    #[[ "$opt_sel_var" -gt 0 && $(eval "printf '%s\n' \${!config_stand_${opt_sel_var}_var[@]}" | grep -Pv '^_' | wc -l) -gt 0 ]] && echo 'Ошибка: был выбран несуществующий вариант развертки стенда. Выход' && exit 1
    [[ "${#opt_stand_nums[@]}" -gt 10 ]] && echo_warn -e "Предупреждение: конфигурация настроена на развертку ${#opt_stand_nums[@]} стендов!\n Развертка более 10 стендов на одном сервере (в зависимости от мощности \"железа\", может и меньше) может вызвать проблемы с производительностью"
    [[ "${#opt_stand_nums[@]}" -gt 100 ]] && echo_err "Ошибка: невозможно (бессмысленно) развернуть на одном стенде более 100 стендов. Выход" && exit 1

    [[ "$1" == 'check-only' ]] && {
        for i in "${script_requirements_cmd[@]}"; do [ ! -x "$(command -v $i )" ] \
                && echo_err "Ошибка: не найдена команда '$i'. На этом хосте установлен PVE (Proxmox VE)?. Конфигурирование стендов невозможно."$'\n'"Необходимые команды для работы: ${script_requirements_cmd[@]}" && exit 1
        done

        pve_ver=$(pvesh get /version --output-format json-pretty | grep -Po '"release"\ *:\ *"\K[^"]+')
        echo $pve_ver | grep -Pq '^([7-9]|[1-9][0-9])\.' || { echo_err "Ошибка: версия PVE '$pve_ver' уже устарела и установка ВМ данным скриптом не поддерживается." && exit 1; }
        create_access_network=$( echo $pve_ver | grep -Pq '^([8-9]|[1-9][0-9])\.' && echo true || echo false )

        [[ "$( echo -n 'тест' | wc -m )" != 4 ]] && {
            echo_warn "Предупреждение: обнаружена проблема с кодировкой. Символы Юникода (в т.ч. кириллические буквы) не будут корректно обрабатываться и строки описаний будут заменены на символы '�'. Попробуйте запустить скрипт другим способом (SSH?)"
            echo
            echo_warn "Warning: An encoding problem has been detected. Unicode characters (including Cyrillic letters) will not be processed correctly and description lines will be replaced with '�' characters. Try running the script in a different way from (SSH?)"
            echo
            opt_rm_tmpfs=false
            ! $silent_mode && { read_question 'Вы хотите продолжить? Do you want to continue?' || exit 0; }
        }
    }

    for check_func in configure_{wan_vmbr,vmid,imgdir,poolname,username,storage,roles}; do
        $opt_verbose && echo "Проверка функционала $check_func"
        $check_func $1
    done

    ! $create_access_network && echo_warn "Предупреждение: версия PVE '$pve_ver' имеет меньший функционал, чем последняя версия PVE и некоторые опции установки будут пропущены"

    [[ "$1" == 'install' ]] && return 0

    local count
    for var in $(compgen -v | grep -P '^config_stand_[1-9][0-9]{0,3}_var$' | awk '{if (NR>1) printf " ";printf $0}'); do
        count=$( eval "printf '%s\n' \${!$var[@]}" | grep -Pv '^_' | wc -l )
        [[ $count != $( eval "printf '%s\n' \${!$var[@]}" | grep -P '^([a-zA-Z0-9](|(-*|\.)(?=[a-zA-Z0-9]))){1,100}$' | wc -l ) ]] \
            && echo_err 'Ошибка: обнаруженны некорректные элементы конфигурации ВМ (имена хостов). Выход' && exit 1
    done

    for desc in pool_desc access_user_desc access_auth_pam_desc access_auth_pve_desc; do
        $opt_verbose && echo "Проверка строки описания на валидность: $desc"
        ! descr_string_check "${config_base[$desc]}" && { echo_err "Ошибка: описание '$desc' некорректно. Выход" && exit 1; }
    done

    [[ "${config_base[access_auth_pam_desc]}" != '' && "${config_base[access_auth_pam_desc]}" == "${config_base[access_auth_pve_desc]}" ]] && echo_err 'Ошибка: выводимое имя типов аутентификации не должны быть одинаковыми' && exit 1

    for val in take_snapshots access_create access_user_enable; do
        $opt_verbose && echo "Проверка зачения конфигурации $val на валидость типу bool"
        ! isbool_check "${config_base[$val]}" && echo_err "Ошибка: зачение переменной конфигурации $val должна быть bool и равляться true или false. Выход" && exit 1
    done

    ! isdigit_check "${config_base[access_pass_length]}" 5 20 && echo_err "Ошибка: значение переменной конфигурации access_pass_length должнно быть числом от 5 до 20. Выход" && exit 1
    isregex_check "[${config_base[access_pass_chars]}]" && deploy_access_passwd test || { echo_err "Ошибка: паттерн regexp '[${config_base[access_pass_chars]}]' для разрешенных символов в пароле некорректен или не захватывает достаточно символов для составления пароля. Выход"; exit 1; }
}

function get_dict_config() {
    [[ "$1" == '' || "$2" == '' ]] && exit 1
    #isdict_var_check "${!2}" || { echo "Ошибка: get_dict_config. Вторая входная переменная не является типом dictionary"; exit 1; }

    local -n "config_var=$1"
    local -n "dict_var=$2"

    [[ "$config_var" == '' ]] && { echo_err "Ошибка: конфиг '$1' пуст"; [[ "$3" == noexit ]] && return 1; exit 1; }
    local var value i=0
    while IFS= read -r line || [[ -n $line ]]; do
        var=$( echo $line | grep -Po '^\s*\K[\w]+(?=\ =\ )' )
        value=$( echo $line | grep -Po '^\s*[\w]+\ =\ \s*\K.*?(?=\s*$)' )
        [[ "$var" == '' && "$value" == '' ]] && continue
        ((i++))
        [[ "$var" == '' || "$value" == '' ]] && echo_err "Ошибка: переменая $1. Не удалось прочитать конфигурацию. Строка $i: '$line'" && exit 1
        dict_var["$var"]="$value" || { echo_err "Ошибка: не удалось записать в словарь"; exit 1; }
    done < <(printf '%s' "$config_var")
}

function get_dict_value() {
    [[ "$1" == '' || "$2" == '' ]] && { echo_err "Ошибка get_dict_value"; exit 1; }

    local -n "config_var1=$1"
    local -A dict
    get_dict_config config_var1 dict noexit
    shift
    while [[ "$1" != '' ]]; do
        [[ "$1" =~ ^[a-zA-Z\_][0-9a-zA-Z\_]{0,32}(\[[a-zA-Z\_][[0-9a-zA-Z\_]{0,32}\])?\=[a-zA-Z\_]+$ ]] || { echo_err "Ошибка get_dict_value: некорректый аргумент '$1'"; exit 1; }
        local -n ref_var="${1%=*}"
        opt_name="${1#*=}"
        for opt in ${!dict[@]}; do
            [[ "$opt" == "$opt_name" ]] && ref_var=${dict[$opt]} && break
        done
        shift
    done
}


function run_cmd() {
    local to_exit=true

    [[ "$1" == '/noexit' ]] && to_exit=false && shift
    [[ "$1" == '/pipefail' ]] && { set -o pipefail; shift; }
    [[ "$1" == '' ]] && echo_err 'Ошибка: run_cmd нет команды'

    local cmd_exec="$@"
    $opt_dry_run && echo "$c_warningВыполнение команды$c_null: $cmd_exec"

    ! $opt_dry_run && {
        local return_cmd=''
        if return_cmd=$( eval $cmd_exec 2>&1 ); then
            $opt_verbose && echo "$c_greenВыполнена команда$c_null: $c_cyan$cmd_exec$c_null"
        else
            ! $to_exit && {
                $opt_verbose && echo "$c_yellowВыполнена команда$c_null: $c_cyan$cmd_exec$c_null"
                echo "${c_red}Error output: $c_warning$return_cmd$c_null"
                return 1
            }
            echo_err "Ошибка выполнения команды: $cmd_exec"
            echo "${c_red}Error output: $c_warning$return_cmd$c_null"
            exit 1
        fi
    }
    return 0
}

function deploy_stand_config() {

    function set_netif_conf() {
        [[ "$1" == '' || "$2" == '' && "$1" != test ]] && echo_err 'Ошибка: set_netif_conf нет аргумента' > /dev/tty && exit 1
        [[ "$1" == 'test' ]] && { [[ "$netifs_type" =~ ^(e1000|e1000-82540em|e1000-82544gc|e1000-82545em|e1000e|i82551|i82557b|i82559er|ne2k_isa|ne2k_pci|pcnet|rtl8139|virtio|vmxnet3)$ ]] && return 0; echo_err "Ошибка: указаный в конфигурации модель сетевого интерфейса '$netifs_type' не является корректным [e1000|e1000-82540em|e1000-82544gc|e1000-82545em|e1000e|i82551|i82557b|i82559er|ne2k_isa|ne2k_pci|pcnet|rtl8139|virtio|vmxnet3]"; exit 1; }

        [[ ! "$1" =~ ^network([0-9]+)$ ]] && { echo_err "Ошибка: опция конфигурации ВМ network некорректна '$1'"; exit 1; }
        local if_num=${BASH_REMATCH[1]} if_desc="$2" create_if=true link_state=''
        for net in "${!Networking[@]}"; do
            [[ "$if_desc" =~ ^\{.*(,\ *state\ *=\ *(up|down)\ *)?\}$ ]]
            [[ "${BASH_REMATCH[2]}" == down ]] && link_state=',link_down=1'
            [[ "${Networking["$net"]}" == "$if_desc" ]] && { cmd_line+=" --net$if_num '${netifs_type:-virtio},bridge=$net$link_state'"; return 0; }
        done

        local iface=''
        if [[ "$if_desc" =~ ^\{\ *bridge\ *=\ *inet\ *(,\ *state\ *=\ *(up|down)\ *)?\}$ ]]; then
            iface="${config_base[inet_bridge]}"
            create_if=false
            [[ "${BASH_REMATCH[2]}" == down ]] && link_state=',link_down=1'
        elif [[ "$if_desc" =~ ^\{\ *bridge\ *=\ *\[\ *([a-zA-Z0-9\_]+)\ *\]\ *(,\ *state\ *=\ *(up|down)\ *)?\}$ ]]; then
            iface=${BASH_REMATCH[1]}
            echo "$pve_net_ifs" | grep -Fxq -- "$iface" || {
                echo_err "Ошибка: указанный статически в конфигурации bridge интерфейс '$iface' не найден"
                exit 1
            }
            create_if=false
            [[ "${BASH_REMATCH[3]}" == down ]] && link_state=',link_down=1'
        else
            [[ "$if_desc" =~ ^\{\ *bridge\ *=\ *\"\ *([^\"]+)\ *\"\ *(,\ *state\ *=\ *(up|down)\ *)?\}$ ]] \
                || { [[ "$if_desc" =~ ^\{.*\}$ ]] && { echo_err "Ошибка: некорректное значение подстановки настройки '$1 = $2' для ВМ '$elem'"; exit 1;}  }
            [[ "${BASH_REMATCH[3]}" == down ]] && link_state=',link_down=1'
            [[ "${BASH_REMATCH[1]}" != '' ]] && if_desc=${BASH_REMATCH[1]}

            for i in ${!vmbr_ids[@]}; do
                [[ -v "Networking[vmbr${vmbr_ids[$i]}]" ]] && continue
                echo "$pve_net_ifs" | grep -Fxq -- "vmbr${vmbr_ids[$i]}" || { local set_id=${vmbr_ids[$i]}; unset 'vmbr_ids[$i]'; break; }
            done
            iface="vmbr$set_id"
        fi
        Networking["$iface"]=$2
        if_desc=${if_desc/\{0\}/$stand_num}
        $create_if && $opt_verbose && echo "Добавление сети vmbr$set_id : '$if_desc'"
        $create_if && { run_cmd /noexit "pvesh create '/nodes/$(hostname)/network' --iface '$iface' --type 'bridge' --autostart 'true' --comments '$if_desc'" \
                || { read -n 1 -p "Интерфейс '$iface' ($if_desc) уже существует! Выход"; exit 1 ;} }

        cmd_line+=" --net$if_num '${netifs_type:-virtio},bridge=$iface$link_state'"

        $create_access_network && ${config_base[access_create]} && { run_cmd /noexit "pveum acl modify '/sdn/zones/localnetwork/$iface' --users '$username' --roles 'PVEAuditor'" || { echo_err "Не удалось создать ACL правило для сетевого интерфейса '$iface' и пользователя '$username'"; exit 1; } }
        return 0

    }

    function set_disk_conf() {
        [[ "$1" == '' || "$2" == '' && "$1" != test ]] && echo_err 'Ошибка: set_disk_conf нет аргумента' > /dev/tty && exit 1
        [[ "$1" == 'test' ]] && { [[ "$disk_type" =~ ^(ide|sata|scsi|virtio)$ ]] && return 0; echo_err "Ошибка: указаный в конфигурации тип диска '$disk_type' не является корректным [ide|sata|scsi|virtio]"; exit 1; }
        [[ ! "$1" =~ ^(boot_|)disk[0-9]+ ]] && { echo_err "Ошибка: неизвестный параметр ВМ '$1'" && exit 1; }
        local _exit=false
        case "$disk_type" in
            ide)    [[ "$disk_num" -le 4  ]] || _exit=true;;
            sata)   [[ "$disk_num" -le 6  ]] || _exit=true;;
            scsi)   [[ "$disk_num" -le 31 ]] || _exit=true;;
            virtio) [[ "$disk_num" -le 16 ]] || _exit=true;;
        esac
        $_exit && { echo_err "Ошибка: невозможно присоедиить больше $((disk_num-1)) дисков типа '$disk_type' к ВМ '$elem'. Выход"; exit 1;}

        if [[ "${BASH_REMATCH[1]}" != boot_ ]] && [[ "$2" =~ ^([0-9]+(|\.[0-9]+))\ *([gG][bB])?$ ]]; then
            cmd_line+=" --${disk_type}${disk_num} '${config_base[storage]}:${BASH_REMATCH[1]},format=$config_disk_format'";
        else
            local file="$2"
            get_file file || exit 1
            cmd_line+=" --${disk_type}${disk_num} '${config_base[storage]}:0,format=$config_disk_format,import-from=$file'"
            [[ "$boot_order" != '' ]] && boot_order+=';'
            boot_order+="${disk_type}${disk_num}"
        fi

        ((disk_num++))
    }

    function set_role_config() {
        [[ "$1" == '' ]] && echo_err 'Ошибка: set_role_conf нет аргумента' > /dev/tty && exit 1
        local roles=$( echo "$1" | sed 's/,/ /g;s/  \+/ /g;s/^ *//g;s/ *$//g' )
        local i role set_role next
        for set_role in $roles; do
            next=false
            for ((i=1; i<=$(echo -n "${roles_list[roleid]}" | grep -c '^'); i++)); do
                role=$( echo "${roles_list[roleid]}" | sed -n "${i}p" )
                [[ "$set_role" != "$role" ]] && continue
                if [[ -v "config_access_roles[$role]" ]]; then
                    [[ "$( echo "${roles_list[privs]}" | sed -n "${i}p" )" != "${config_access_roles[$role]}" ]] \
                        && run_cmd "pvesh set '/access/roles/$role' --privs '${config_access_roles[$role]}'"
                    next=true
                else
                    echo_err "Ошибка: в конфигурации для установки ВМ '$elem' установлена несуществующая access роль '$role'. Выход"
                    exit 1
                fi
                break
            done
            ! $next && run_cmd "pvesh create /access/roles --roleid '$role' --privs '${config_access_roles[$role]}'"
        done
    }

    function set_machine_type() {
        [[ "$1" == '' ]] && echo_err 'Ошибка: set_disk_conf нет аргумента' && exit 1
        local machine_list=$( qemu-kvm -machine help | awk 'NR>1{print $1}' )
        local type=$1
        if ! echo "$machine_list" | grep -Fxq "$type"; then
            if [[ "$type" =~ ^((pc)-i440fx|pc-(q35))-[0-9]+.[0-9]+$ ]]; then
                type=${BASH_REMATCH[2]:-${BASH_REMATCH[3]}}
                echo_warn "[Предупреждение]: в конфигурации ВМ '$elem' указанный тип машины '$1' не существует в этой версии PVE/QEMU. Заменен на последнюю доступную версию: 'pc-${type/pc/i440fx}'"
            else
                echo_err "Ошибка: в конфигурации ВМ '$elem' указан неизвестный тип машины '$1'. Ошибка или старая версия PVE?. Выход"
                exit 1
            fi
        fi
        cmd_line+=" -machine '$type'"
    }

    [[ "$1" == '' ]] && echo_err "Внутренняя ошибка скрипта установки стенда" && exit 1

    local -n "config_var=config_stand_${opt_sel_var}_var"
    local -A Networking=()

    local stand_num=$1
    local vmid=$((${config_base[start_vmid]} + $1 * 100 + 1))
    [[ "$stands_group" == '' ]] && { echo_err "Ошибка: не указана группа стендов"; exit 1; }
    local pool_name="${config_base[pool_name]/\{0\}/$stand_num}"

    local pve_net_ifs=''
    parse_noborder_table 'pvesh get /nodes/$(hostname)/network' pve_net_ifs iface

    run_cmd /noexit "pveum pool add '$pool_name' --comment '${config_base[pool_desc]/\{0\}/$stand_num}'" || { echo_err "Ошибка: не удалось создать пул '$pool_name'"; exit 1; }
    run_cmd "pveum acl modify '/pool/$pool_name' --propagate 'false' --groups '$stands_group' --roles 'NoAccess'"


    ${config_base[access_create]} && {
        local username="${config_base[access_user_name]/\{0\}/$stand_num}@pve"
        run_cmd /noexit "pveum user add '$username' --enable '${config_base[access_user_enable]}' --comment '${config_base[access_user_desc]/\{0\}/$stand_num}' --groups '$stands_group'" \
            || { echo_err "Ошибка: не удалось создать пользователя '$username'"; exit 1; }
        run_cmd "pveum user modify '$username' --comment '${config_base[access_user_desc]/\{0\}/$stand_num}'"
        run_cmd "pveum acl modify '/pool/$pool_name' --users '$username' --roles 'PVEAuditor' --propagate 'false'"
    }

    for elem in $(printf '%s\n' "${!config_var[@]}" | grep -P '^[^_]' | sort); do

        local cmd_line=''
        local netifs_type='virtio'
        local disk_type='scsi'
        local disk_num=0
        local boot_order=''
        local -A vm_config=()
        local cmd_line="qm create '$vmid' --name '$elem' --pool '$pool_name'"

        get_dict_config "config_stand_${opt_sel_var}_var[$elem]" vm_config

        [[ "${vm_config[config_template]}" != '' ]] && {
            [[ -v "config_templates[${vm_config[config_template]}]" ]] || { echo_err "Ошибка: шаблон конфигурации '${vm_config[config_template]}' для ВМ '$elem' не найден. Выход"; exit 1; }
            get_dict_config "config_templates[${vm_config[config_template]}]" vm_config
            unset -v 'vm_config[config_template]';
        }
        [[ "${vm_config[netifs_type]}" != '' ]] && netifs_type="${vm_config[netifs_type]}" && unset -v 'vm_config[netifs_type]'
        [[ "${vm_config[disk_type]}" != '' ]] && disk_type="${vm_config[disk_type]}" && unset -v 'vm_config[disk_type]'

        set_netif_conf test && set_disk_conf test || exit 1

        for opt in $(printf '%s\n' "${!vm_config[@]}" | sort); do
            case "$opt" in
                startup|tags|ostype|serial0|serial1|serial2|serial3|agent|scsihw|cpu|cores|memory|bios|bwlimit|description|args|arch|vga|kvm|rng0|acpi)
                    cmd_line+=" --$opt '${vm_config[$opt]}'";;
                network*) set_netif_conf "$opt" "${vm_config[$opt]}";;
                boot_disk*|disk*) set_disk_conf "$opt" "${vm_config[$opt]}";;
                access_roles) ${config_base[access_create]} && set_role_config "${vm_config[$opt]}";;
                machine) set_machine_type "${vm_config[$opt]}";;
                *) echo_warn "[Предупреждение]: обнаружен неизвестный параметр конфигурации '$opt = ${vm_config[$opt]}' ВМ '$elem'. Пропущен"
            esac
        done
        [[ "$boot_order" != '' ]] && cmd_line+=" --boot order=$boot_order"

        run_cmd /noexit "$cmd_line " || { echo_err "Ошибка: не удалось создать ВМ '$elem' стенда '$pool_name'. Выход"; exit 1; }

        [[ "$acc_roles" != '' ]] && run_cmd "pveum acl modify '/vms/$vmid' --roles '$acc_roles' --users '$username'"

        ${config_base[take_snapshots]} && run_cmd /pipefail "qm snapshot '$vmid' 'Start' --description 'Исходное состояние ВМ' | tail -n2"
        echo "$c_green[Выполнено]$c_null: $c_cyanКонфигурирование VM $elem завершено$c_null"
        ((vmid++))
    done

    [[ "${#Networking[@]}" != 0 ]] && run_cmd "pvesh set '/nodes/$(hostname)/network'"

    echo "$c_green[Выполнено]$c_null: $c_cyanКонфигурирование стенда $stand_num завершено$c_null"
}

function deploy_access_passwd() {

    local passwd_chars='0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ":;< ,.?№!@#$%^&*()[]{}-_+=\|/~`абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦШЩЪЫЬЭЮЯ'\'
    passwd_chars=$(echo $passwd_chars | grep -Po "[${config_base[access_pass_chars]}]" | tr -d '\n')

    [[ "$1" == test ]] && { [[ $(echo -n "$passwd_chars" | wc -m) -ge 1 ]] && return 0 || return 1; }
    [[ "${#opt_stand_nums[@]}" == 0 ]] && return 0

    local format_opt=1
    ! $silent_mode && {
        echo $'\n\n\n'"Выберите вид отображения учетных данных (логин/паролей) для доступа к стендам:"
        echo "  1. Обычный   ${c_value}{username} : {passwd}$c_null"
        echo "  2. Вариант для вставки в Excel: ${c_value}{pve_url}  {username}  {passwd}$c_null"
        echo "  3. Вариант для вставки в Excel (с заголовками к каждой записи, для печати): ${c_value}{pve_url}  {username}  {passwd}$c_null"
        #echo '  4. Текстово-табличный вариант (для печати с блокнота)'
        #echo '  5. Текстово-табличный вариант (для печати с блокнота, с заголовками к каждой записи)'
        echo
        format_opt=$(read_question_select 'Вариант отображения' '^([1-3]|)$' )
    }

    [[ $format_opt == '' ]] && format_opt=1

    [[ $format_opt != 1 ]] && {
        local -A pve_nodes; local i pve_url
        parse_noborder_table 'pvesh get /cluster/status' pve_nodes ip local
        for ((i=1; i<=$( echo -n "${pve_nodes[ip]}" | grep -c '^' ); i++)); do
            [[ "$( echo -n "${pve_nodes[local]}" | sed -n "${i}p" )" == '1' ]] && pve_url="https://$( echo -n "${pve_nodes[ip]}" | sed -n "${i}p" ):8006" && break
        done
        local val=$(read_question_select "Введите отображаемый адрес (URL) сервера Proxmox VE [$pve_url]")
        [[ "$val" != '' ]] && pve_url=$val
    }

    local nl=$'\n' tab=$'\t'
    local table=$nl$nl
    case $format_opt in
        2) table+="\"Адрес сервера\"$tab\"Имя пользователя\"$tabПароль$nl";;
        #4|5)
    esac

    for stand_num in "${opt_stand_nums[@]}"; do
        [[ "$1" != set ]] && username="${config_base[access_user_name]/\{0\}/$stand_num}@pve" || username=$stand_num
        [[ $format_opt == 3 ]] && table+="\"Адрес сервера\"$tab\"Имя пользователя\"$tabПароль$nl"

        local passwd=$(
        for i in $( eval echo {1..${config_base[access_pass_length]}} ); do
            echo -n "${passwd_chars:RANDOM%${#passwd_chars}:1}"
        done )

        run_cmd /noexit "pvesh set /access/password --userid '$username' --password '$passwd'" || { echo_err "Ошибка: не удалось установить пароль пользователю $username"; exit 1; }
        case $format_opt in
            1) table+="$tab$username : $passwd$nl";;
            2|3) table+="$pve_url$tab$username$tab$passwd$nl";;
        esac
    done
    echo "$table"

}

function install_stands() {

    is_show_config=false

    configure_varnum
    configure_standnum
    check_config install

    local val=''
    for opt in pool_desc access_user_desc; do
        get_dict_value "config_stand_${opt_sel_var}_var[_stand_config]" "val=$opt"
        descr_string_check "$val" && [[ "$val" != '' ]] && config_base["$opt"]=$val
    done
    show_config

    ! $silent_mode && read_question 'Хотите изменить другие параметры?' && {
        local opt_names=( pool_name pool_desc storage inet_bridge take_snapshots access_{create,user_{name,desc,enable},pass_{length,chars},auth_{pve,pam}_desc} dry-run )
        while true; do
            show_config install-change
            echo
            local switch=$( read_question_select 'Выберите номер настройки для изменения' '^[0-9]+$' 0 $( ${config_base[access_create]} && echo 14 || echo 7 ) )
            echo
            [[ "$switch" == 0 ]] && break
            [[ "$switch" -ge 7 && "${config_base[access_create]}" == false ]] && (( switch+=7 ))
            local opt=$( printf '%s\n' "${opt_names[@]}" | sed "$switch!D" )
            val=''
            case $opt in
                pool_name) configure_poolname set install exit false; continue;;
                access_user_name) configure_username set install exit false; continue;;
                storage) config_base[storage]='{manual}'; configure_storage install; continue;;
                inet_bridge) configure_wan_vmbr manual; continue;;
                take_snapshots|access_create|access_user_enable) config_base[$opt]=$( invert_bool ${config_base[$opt]} ); continue;;
                dry-run) opt_dry_run=$( invert_bool $opt_dry_run ); continue;;
            esac
            val=$( read_question_select "${config_base[_$opt]:-$opt}" )
            case $opt in
                pool_desc|access_user_desc|access_auth_pve_desc|access_auth_pam_desc)
                    (config_base[$opt]="$val"; [[ "${config_base[access_auth_pam_desc]}" != '' && "${config_base[access_auth_pam_desc]}" == "${config_base[access_auth_pve_desc]}" ]] && echo_err 'Ошибка: видимые имена типов аутентификации не должны быть одинаковыми' ) && continue

                    descr_string_check "$val" || { echo_err 'Ошибка: введенное значение является некорректным'; continue; };;
                access_pass_length) isdigit_check "$val" 5 20 || { echo_err 'Ошибка: допустимая длина паролей от 5 до 20'; continue; } ;;
                access_pass_chars) isregex_check "[$val]" && ( config_base[access_pass_chars]="$val"; deploy_access_passwd test ) || { echo_err 'Ошибка: введенное значение не является регулярным выражением или не захватывает достаточно символов для составления пароля'; continue; } ;;
                *) echo_err 'Внутреняя ошибка скрипта. Выход'; exit 1;;
            esac
            [[ $opt == access_create ]] && ! ${config_base[access_create]} && $val && \
                { configure_username set-install exit false || configure_username set set-install exit false || continue; }
            echo test
            config_base[$opt]="$val"
        done
        show_config
    }
    local stand_num
    local stands_group=${config_base[pool_name]/\{0\}/"X"}
    local vmbr_ids=( {{1001..9999},{0000..0999},{00..09},{010..099},{0..1000}} )

    get_dict_value "config_stand_${opt_sel_var}_var[_stand_config]" "val=stands_display_desc"
    [[ "$val" == '' ]] && val=$(eval echo "\$_config_stand_${opt_sel_var}_var")
    [[ "$val" == '' ]] && val=${config_base[pool_name]}

    $opt_dry_run && echo_warn '[Предупреждение]: включен режим dry-run. Никакие изменения в конфигурацию/ВМ внесены не будут'
    echo "Для выхода из программы нажмите Ctrl-C"
    ! $silent_mode && { read_question 'Начать установку?' || exit 0; }
    $silent_mode && { echo $'\n'"10 секунд для проверки правильности конфигурации"; sleep 10; }

    # Начало установки
    run_cmd /noexit "( pveum group add '$stands_group' --comment '$val'          2>&1;echo) | grep -Poq '(^$|already\ exists$)'" \
        || { echo_err "Ошибка: не удалось создать access группу для стендов '$stands_group'. Выход"; exit 1; }

    local -A roles_list
    parse_noborder_table 'pveum role list' roles_list

    opt_not_tmpfs=false

    for stand_num in "${opt_stand_nums[@]}"; do
        deploy_stand_config $stand_num
    done
    ${config_base[access_create]} && {
        [[ "${config_base[access_auth_pam_desc]}" != '' ]] && run_cmd "pveum realm modify pam --comment '${config_base[access_auth_pam_desc]}'"
        [[ "${config_base[access_auth_pve_desc]}" != '' ]] && run_cmd "pveum realm modify pve --default 'true' --comment '${config_base[access_auth_pve_desc]}'"
    }

    deploy_access_passwd

    echo $'\n'"$c_greenУстановка закочена.$c_null Выход"

}

#       pvesh set /cluster/options --tag-style 'color-map=alt_server:ffcc14;alt_workstation:ac58e4,ordering=config,shape=none'


function check_arg() {
    [[ "$1" == '' || "${1:0:1}" == '-' ]] && echo_err "Ошибка обработки аргуметов: ожидалось значение. Выход" && exit 1
}

#TODO
function manage_stands() {

    local -A acl_list
    local -A group_list

    local -A print_list
    local -A user_list
    local -A pool_list

    parse_noborder_table 'pveum group list' group_list groupid users comment
    parse_noborder_table 'pveum acl list' acl_list

    local group_name pool_name comment users
    local users_count=0 stands_count=0

    for ((i=1; i<=$(echo -n "${acl_list[path]}" | grep -c '^'); i++)); do
        [[ "$(echo "${acl_list[type]}" | sed -n "${i}p")" != group ]] && continue
        group_name=$(echo "${acl_list[ugid]}" | sed -n "${i}p")
        pool_name="$(echo "${acl_list[path]}" | sed -n "${i}p")"
        if [[ "$pool_name" =~ ^\/pool\/(.+) ]] \
            && [[ "$(echo "${acl_list[roleid]}" | sed -n "${i}p")" == NoAccess ]] \
            && [[ "$(echo "${acl_list[propagate]}" | sed -n "${i}p")" == 0 ]]; then
            print_list["$group_name"]=''
            pool_list["$group_name"]+=" ${BASH_REMATCH[1]} "
            pool_list["$group_name"]=$( echo "${pool_list[$group_name]}" | tr ' ' '\n' | sed '/^$/d' | sort -u )
        fi
    done

    for ((i=1; i<=$(echo -n "${group_list[groupid]}" | grep -c '^'); i++)); do
        group_name=$(echo "${group_list[groupid]}" | sed -n "${i}p")
        [[ -v "print_list[$group_name]" ]] && {
            comment=$(echo "${group_list[comment]}" | sed -n "${i}p")
            users=$(echo "${group_list[users]}" | sed -n "${i}p")
            print_list["$group_name"]="$c_lgreen$group_name$c_null : $comment"
            user_list["$group_name"]=$( echo "$users" | tr -s ',' '\n' | sort -u )
        }
    done

    [[ ${#print_list[@]} != 0 ]] && echo $'\n\nСписок развернутых конфигураций:' || { echo_warn "Ни одной конфигурации не было найдено. Выход"; exit; }
    local i=0
    for item in ${!print_list[@]}; do
        echo "  $((++i)). ${print_list[$item]}"
    done
    [[ $i -gt 1 ]] && i=$( read_question_select 'Выберите номер конфигурации' '^[0-9]+$' 1 $i )
    local j=0
    group_name=''
    for item in ${!print_list[@]}; do
        ((j++))
        [[ $i != $j ]] && continue
        group_name=$item
        break
    done

    echo $'\nУправление конфигурацией:'
    echo '  1. Включение учетных записей'
    echo '  2. Отключение учетных записей'
    echo '  3. Установка паролей для учетных записей'
    echo '  4. Откатить виртуальные машины до снапшота Start'
    echo '  5. Удаление стендов'
    local switch=$(read_question_select $'\nВыберите действие' '^[1-5]$' )

    if [[ $switch =~ [1-3] ]]; then
        local user_name enable state usr_range='' usr_count=$(echo -n "${user_list[$group_name]}" | grep -c '^') usr_list=${user_list[$group_name]}

        [[ "$usr_count" == 0 ]] && echo_err "Ошибка: пользователи стендов '$group_name' не найдены. Выход" && exit 1
        if [[ "$usr_count" -gt 1 ]]; then
            echo $'\nВыберите пользователей для конфигурирования:'
            for ((i=1; i<=$usr_count; i++)); do
                echo "  $i. $(echo "${user_list[$group_name]}" | sed -n "${i}p" )"
            done
            echo $'\nДля выбора всех пользователей нажмите Enter'
            while true; do
                usr_range=$( read_question_select 'Введите номера выбранных пользователей (прим 1,2-10)' '\A^(([0-9]{1,3}((\-|\.\.)[0-9]{1,3})?([\,](?!$\Z)|(?![0-9])))+|)$\Z' )
                [[ "$usr_range" == '' ]] && break

                local numarr=( $( get_numrange_array "$usr_range") )
                usr_list=${user_list[$group_name]}
                for ((i=1; i<=$(echo -n "$usr_list" | grep -c '^'); i++)); do
                    printf '%s\n' "${numarr[@]}" | grep -Fxq "$i" || { usr_list=$(echo "$usr_list" | sed -n "${i}!p" ); (( i > 0 ? i-- : i )); }
                done
                [[ "$usr_list" != '' ]] && break || echo_warn "Не выбран ни один пользователь!"
            done
            user_list[$group_name]=$usr_list
        fi

        echo -n $'\nВыбранные пользователи: '; get_val_print "$(echo ${user_list[$group_name]} )"

        opt_stand_nums=()
        for ((i=1; i<=$(echo -n "${user_list[$group_name]}" | grep -c '^'); i++)); do
            user_name=$(echo "${user_list[$group_name]}" | sed -n "${i}p" )
            [[ $switch != 3 ]] && {
                [[ $switch == 1 ]] && { enable=true;state="$c_lgreenвключен"; }; [[ $switch == 2 ]] && { enable=false; state="$c_lredвыключен"; }
                run_cmd /noexit "pveum user modify '$user_name' --enable '$enable'" || { echo_err "Ошибка: не удалось изменить enable для пользователя '$user_name'"; }
                echo "$user_name : $state$c_null";
                continue
            }
            opt_stand_nums+=( "$user_name" )
        done

        if [[ $switch == 3 ]]; then
            local switch=0 val='' opt=''
            while true; do
                show_config passwd-change
                switch=$( read_question_select 'Выбранный пункт конфигурации' '^([0-9]+|)$' 0 2 )
                [[ "$switch" == 0 || "$switch" == '' ]] && break
                case "$switch" in
                    1) opt='access_pass_length';;
                    2) opt='access_pass_chars';;
                esac
                val=$( read_question_select "${config_base[_$opt]:-$opt}" )
                case "$switch" in
                    1) isdigit_check "$val" 5 20 || { echo_err 'Ошибка: допустимая длина паролей от 5 до 20'; continue; };;
                    2) isregex_check "[$val]" && ( config_base[access_pass_chars]="$val"; deploy_access_passwd test ) || { echo_err "Ошибка: '[$val]' не является регулярным выражением или или не захватывает достаточно символов для составления пароля"; continue; };;
                esac
                config_base["$opt"]=$val
            done
            deploy_access_passwd set
        fi
        echo $'\n'"$c_greenНастройка завершена.$c_null Выход" && exit 0
    fi

    local stand_range='' stand_count=$(echo -n "${pool_list[$group_name]}" | grep -c '^') stand_list='' usr_list=''

    [[ "$stand_count" == 0 ]] && echo_err "Ошибка: пулы стендов '$group_name' не найдены. Выход" && exit 1
    if [[ "$stand_count" -gt 1 ]]; then
        echo $'\nВыберите стеды для управления:'
        for ((i=1; i<=$stand_count; i++)); do
            echo "  $i. $(echo "${pool_list[$group_name]}" | sed -n "${i}p" )"
        done
        echo $'\nДля выбора всех стендов группы нажмите Enter'
        while true; do
            stand_range=$( read_question_select 'Введите номера выбранных стендов (прим 1,2-10)' '\A^(([0-9]{1,3}((\-|\.\.)[0-9]{1,3})?([\,](?!$\Z)|(?![0-9])))+|)$\Z' )
            stand_list=${pool_list[$group_name]}
            usr_list=${user_list[$group_name]}
            [[ "$stand_range" == '' ]] && break

            local numarr=( $( get_numrange_array "$stand_range") )
            for ((i=1; i<=$(echo -n "$stand_list" | grep -c '^'); i++)); do
                printf '%s\n' "${numarr[@]}" | grep -Fxq "$i" || {
                    local stand_name=$(echo "$stand_list" | sed -n "${i}p")
                    stand_list=$(echo "$stand_list" | sed -n "${i}!p" )
                    (( i > 0 ? i-- : i ))
                    local j=1
                    for ((j=1; j<=$(echo -n "${acl_list[path]}" | grep -c '^'); j++)); do
                        local path=$( echo "${acl_list[path]}" | sed -n "${j}p" )
                        [[ "$path" == "/pool/$stand_name" && "$( echo "${acl_list[type]}" | sed -n "${j}p" )" == user ]] || continue
                        local user=$( echo "${acl_list[ugid]}" | sed -n "${j}p" )
                        usr_list=$(echo "$usr_list" | sed '/^'$user'$/d')
                    done
                }
            done
            [[ "$stand_list" != '' ]] && break || echo_warn "Не выбран ни один стенд!"
        done
        [[ "${pool_list[$group_name]}" == "$stand_list" ]] && local del_all=true
        user_list[$group_name]=$usr_list
        pool_list[$group_name]=$stand_list
    else
        local del_all=true
    fi

    echo -n $'\nВыбранные стенды: '; get_val_print "$(echo ${pool_list[$group_name]} )"

    local regex='\s*\"{opt_name}\"\s*:\s*(\K[0-9]+|\"\K(?(?=\\").{2}|[^"])+)'

    if [[ $switch == 4 ]]; then
        local vmid pool_info vmid_list vmname_list status name
        for ((i=1; i<=$( echo -n "${pool_list[$group_name]}" | grep -c '^' ); i++)); do
            echo
            pool_name=$( echo "${pool_list[$group_name]}" | sed -n "${i}p" )
            pool_info=$( pvesh get "/pools/$pool_name" --output-format json-pretty ) || { echo_err "Ошибка: не удалось получить информацию об стенде '$pool_name'"; exit 1; }
            vmid_list=$( echo "$pool_info" | grep -Po "${regex/\{opt_name\}/vmid}" )
            vmname_list=$( echo "$pool_info" | grep -Po "${regex/\{opt_name\}/name}" )

            for ((j=1; j<=$( echo -n "$vmid_list" | grep -c '^' ); j++)); do
                vmid=$( echo "$vmid_list" | sed -n "${j}p" )
                name=$( echo "$vmname_list" | sed -n "${j}p" )

                status=$( run_cmd /noexit "qm rollback '$vmid' 'Start' 2>&1" ) && {
                    echo "[${c_green}Выполнено$c_null]: стенд ${c_value}$pool_name$c_null машина ${c_lgreen}$name$c_null (${c_lcyan}$vmid$c_null)"
                    continue
                }
                echo "$status" | grep -Pq $'^Configuration file \'[^\']+\' does not exist$' && echo_err "Ошибка: ВМ $name ($vmid) стенда $pool_name не существует!" && continue
                echo "$status" | grep -P $'^snapshot \'[^\']+\' does not exist$' && echo_err "Ошибка: Снапшот ВМ $name ($vmid) стенда $pool_name не существует!"
            done
        done
    fi

    if [[ $switch == 5 ]]; then

        echo -n $'Выбранные пользователи: '; get_val_print "$(echo ${user_list[$group_name]} )"
        read_question $'\nВы действительно хотите продолжить?' || exit 0

        local -A ifaces_info
        local pool_info vmid_list vmname_list vmid vm_netifs ifname deny_ifaces bridge_ports k restart_network=false
        parse_noborder_table 'pvesh get /nodes/$(hostname)/network' ifaces_info iface bridge_ports address address6 || { echo_err "Ошибка: не удалось получить информацию об сетевых интерфейсах"; exit 1; }

        for ((i=1; i<=$( echo -n "${ifaces_info[iface]}" | grep -c '^' ); i++)); do
            bridge_ports=$( echo "${ifaces_info[bridge_ports]}" | sed -n "${i}p" )
            ifname=$( echo "${ifaces_info[iface]}" | sed -n "${i}p" )
            [[ "$bridge_ports" != '' || "$( echo "${ifaces_info[address]}" | sed -n "${i}p" )" != '' \
                || "$( echo "${ifaces_info[address6]}" | sed -n "${i}p" )" != '' ]] && {
                    deny_ifaces+=" $ifname $bridge_ports"
            }
        done
        echo
        unset ifaces_info bridge_ports
        for ((i=1; i<=$( echo -n "${pool_list[$group_name]}" | grep -c '^' ); i++)); do
            echo
            pool_name=$( echo "${pool_list[$group_name]}" | sed -n "${i}p" )
            pool_info=$( pvesh get "/pools/$pool_name" --output-format json-pretty ) || { echo_err "Ошибка: не удалось получить информацию об стенде '$pool_name'"; exit 1; }
            vmid_list=$( echo "$pool_info" | grep -Po "${regex/\{opt_name\}/vmid}" )
            vmname_list=$( echo "$pool_info" | grep -Po "${regex/\{opt_name\}/name}" )

            for ((j=1; j<=$( echo -n "$vmid_list" | grep -c '^' ); j++)); do
                vmid=$( echo "$vmid_list" | sed -n "${j}p" )
                name=$( echo "$vmname_list" | sed -n "${j}p" )
                vm_netifs=$( pvesh get /nodes/$(hostname)/qemu/$vmid/config --output-format json-pretty ) || { echo_err "Ошибка: не удалось получить информацию об ВМ стенда '$pool_name'"; exit 1; }
                vm_netifs=$( echo "$vm_netifs" | grep -Po '\s*\"net[0-9]+\"\s*:\s*(\".*?bridge=\K\w+)' )

                for ((k=1; k<=$( echo -n "$vm_netifs" | grep -c '^' ); k++)); do
                    ifname=$( echo "$vm_netifs" | sed -n "${k}p" )
                    echo "$deny_ifaces" | grep -Pq '(?<=^| )'$ifname'(?=$| )' && continue
                    run_cmd /noexit "( pvesh delete '/nodes/$(hostname)/network/$ifname'       2>&1;echo) | grep -Pq '(^$|interface does not exist$)'" \
                        || { echo_err "Ошибка: не удалось удалить сетевой интерфейс '$ifname'"; exit 1; }
                    deny_ifaces+=" $ifname"
                    restart_network=true
                done

                run_cmd /noexit "( qm destroy '$vmid' --skiplock 'true' --purge 'true' 2>&1;echo) | grep -Pq '(^$|does not exist$)'" \
                    || { echo_err "Ошибка: не удалось удалить ВМ '$vmid' стенда '$pool_name'"; exit 1; }
            done

            run_cmd /noexit "( pveum pool modify '$pool_name' --delete 'true' --storage '"$( echo "$pool_info" | grep -Po "${regex/\{opt_name\}/storage}" )"' 2>&1;echo) | grep -Pq '(^$|is not a pool member$)'" \
                || { echo_err "Ошибка: не удалось удалить привязку хранилищ от пула стенда '$pool_name'"; exit 1; }
            run_cmd /noexit "( pveum pool delete '$pool_name' 2>&1;echo) | grep -Pq '(^$|does not exist$)'" \
                    || { echo_err "Ошибка: не удалось удалить пул стенда '$pool_name'"; exit 1; }
        done

        for ((i=1; i<=$( echo -n "${user_list[$group_name]}" | grep -c '^' ); i++)); do
            user_name=$( echo "${user_list[$group_name]}" | sed -n "${i}p" )
            run_cmd /noexit "pveum user delete '$user_name'" || { echo_err "Ошибка: не удалось удалить пользователя '$user_name' стенда '$pool_name'"; exit 1; }
        done

        local roles_list_after list_roles
        parse_noborder_table 'pveum acl list' roles_list_after roleid
        for role in $( echo "$roles_list_after" | sort -u ); do
            echo "$roles_list_after" | grep -Fxq "$role" || {
                [[ "$list_roles" == '' ]] && { list_roles=$( pveum role list --output-format yaml | grep -v - | grep -Po '^\s*(roleid|special)\s*:\s*\K.*' ) || exit 1; }
                echo "$list_roles" | grep -Pzq '(^|\n)'$role'\n0' && run_cmd "pveum role delete '$role'"
            }
        done

        [[ "$del_all" == true ]] && run_cmd "pveum group delete '$group_name'"

        $restart_network && run_cmd "pvesh set '/nodes/$(hostname)/network'"
    fi

    echo $'\n'"$c_lgreenНастройка завершена.$c_null Выход"
}


conf_files=()
_opt_show_help='Вывод в терминал справки по команде, а так же примененных значений конфигурации и выход'
opt_show_help=false
_opt_show_config='Вывод в терминал (или файл) примененных значений конфигурации и выход'
opt_show_config=false

_opt_silent_install='Произвести установку стенда в "тихом" режиме без интерактивного ввода'
opt_silent_install=false
_opt_silent_control=$'Управление настройками уже развернутых стендов (применение настроек, управление пользователями).\n\tБез интерактивного ввода (через аргументы командной строки и конфигурационные файлы)'
opt_silent_control=false
_opt_verbose='Вывод параметров конфигурации и более подробный вывод сообщений'
opt_verbose=false
_opt_zero_vms=$'Очищает конфигурацию ВМ. Срабатывает при применении конфигурации из файла'
opt_zero_vms=false
_opt_stand_nums='Кол-во разворачиваемых стендов. Числа от 0 до 99. Списком, напр.: 1-6,8'
opt_stand_nums=()
_opt_rm_tmpfs='Не удалять временный раздел после установки'
opt_rm_tmpfs=true
# состояние скрипта, при котором запрос ан удаление tmpfs бессмыслен (в меню и пр)
opt_not_tmpfs=true
_opt_dry_run='Запустить установку в тестовом режиме, без реальных изменений'
opt_dry_run=false

_opt_sel_var='Выбор варианта установки стендов'
opt_sel_var=0

# список скачанных файлов
declare -A list_url_files

# Обработка аргуметов командой строки
switch_action=0
iteration=1
i=0
while [ $# != 0 ]; do
    ((i++))
    case $iteration in
        1)  if [[ "${!i}" == '-z' || "${!i}" == '--clear-vmconfig' ]]; then opt_zero_vms=true; set -- "${@:1:i-1}" "${@:i+1}"; fi;;
        2)  if [[ "${!i}" == '-c' || "${!i}" == '--config' ]]; then
            ((i++)); set_configfile "${!i}"; set -- "${@:1:i-2}" "${@:i+1}"; fi;;
        *)  case $1 in
                \?|-\?|/\?|-h|/h|--help) opt_show_help=true;;
                -sh|--show-config) opt_show_config=true
                    [[ "$2" =~ ^[^-].* ]] && conf_files+=("$2") && shift;;
                -v|--verbose)           opt_verbose=true;;
                -n|--stand-num)         check_arg "$2"; set_standnum "$2"; shift;;
                -var|--set-var-num)     check_arg "$2"; set_varnum "$2"; shift;;
                -si|--silent-install)   opt_silent_install=true; switch_action=1;;
                --dry-run)              opt_dry_run=true;;
                -vmbr|--wan-bridge)     check_arg "$2"; config_base[inet_bridge]="$2"; shift;;
                -vmid|--start-vm-id)    check_arg "$2"; config_base[start_vmid]="$2"; shift;;
                -dir|--mk-tmpfs-dir)    check_arg "$2"; config_base[mk_tmpfs_imgdir]="$2"; shift;;
                -norm|--no-clear-tmpfs) opt_rm_tmpfs=false;;
                -st|--storage)          check_arg "$2"; config_base[storage]="$2"; shift;;
                -pn|--pool-name)        check_arg "$2"; config_base[pool_name]="$2"; shift;;
                -snap|--take-snapshots) check_arg "$2"; config_base[take_snapshots]="$2"; shift;;
                -acl|--access-create)   check_arg "$2"; config_base[access_create]="$2"; shift;;
                -u|--user-name)         check_arg "$2"; config_base[access_user_name]="$2"; shift;;
                -l|--pass-length)       check_arg "$2"; config_base[access_pass_length]="$2"; shift;;
                -char|--pass-chars)     check_arg "$2"; config_base[access_pass_chars]="$2"; shift;;
                -sctl|--silent-control) opt_silent_control=true;;
                *) echo_err "Ошибка: некорректный аргумент: $1. Выход"; exit;;
            esac
            shift;;
    esac
    if [[ $i -ge $# ]]; then ((iteration++)); i=0; fi
done

silent_mode=$opt_silent_install || $opt_silent_control



check_config

if $opt_show_help; then show_help; show_config; exit; fi

if $opt_show_config; then
    show_config detailed
    for file in ${conf_files[@]}; do
        show_config detailed | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2};?)?)?[mGK]//g;s/\r//g" > $file
    done
    exit
#else show_config
fi

$opt_silent_install || switch_action=$(read_question_select $'\nДействие: 1 - Развертывание стендов, 2 - Управление стендами' '^[1-2]$' )

case $switch_action in
    1) install_stands;;
    2) manage_stands;;
    *) echo_warn 'Функционал в процессе разработки и пока недоступен. Выход'; exit 0;;
esac

configure_imgdir clear

