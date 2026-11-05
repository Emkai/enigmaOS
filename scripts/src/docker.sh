#!/usr/bin/env bash

docker_service_running() {
    systemctl is-active --quiet docker.service
}

docker_notify() {
    notify-send "Docker" "$1"
}

docker_try() {
    local out
    if ! out=$("$@" 2>&1); then
        docker_notify "${out:-$* failed}"
        return 1
    fi
}

docker_sudo() {
    if sudo -n true 2>/dev/null; then
        docker_try sudo -n "$@"
        return
    fi
    local pw
    pw="$(qs_menu_password "sudo password")"
    [[ -z "$pw" ]] && return 1
    local out
    if ! out=$(printf '%s\n' "$pw" | sudo -S -p '' "$@" 2>&1); then
        docker_notify "${out:-$* failed}"
        return 1
    fi
}

docker_service_start() {
    docker_sudo systemctl start docker.socket docker.service
}

docker_service_stop() {
    docker_sudo systemctl stop docker.service docker.socket
}

docker_term() {
    setsid -f kitty --title "$1" "${@:2}" >/dev/null 2>&1
}

docker_containers() {
    docker ps -a --format '{{.Names}}\t{{.State}}\t{{.Image}}' |
        awk -F'\t' '{ print ($2 == "running" ? 0 : 1) "\t" $0 }' | sort -t$'\t' -k1,1 -k2,2 | cut -f2-
}

docker_container_info() {
    docker inspect -f '{{.State.Status}}|{{.Image}}|{{.Config.Image}}|{{index .Config.Labels "com.docker.compose.project"}}|{{range $k, $v := .NetworkSettings.Networks}}{{$v.IPAddress}} {{end}}|{{range $p, $b := .NetworkSettings.Ports}}{{if $b}}{{(index $b 0).HostPort}}->{{$p}} {{end}}{{end}}' "$1" 2>/dev/null
}

docker_compose_projects() {
    docker compose ls -a --format json 2>/dev/null | jq -r '.[] | [.Name, .Status, .ConfigFiles] | @tsv'
}

docker_images_list() {
    docker images --filter dangling=false --format '{{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}'
}

docker_volumes_list() {
    docker volume ls --format '{{.Name}}\t{{.Driver}}'
}

docker_networks_list() {
    docker network ls --format '{{.Name}}\t{{.Driver}}'
}
