#!/bin/bash

# Default values
KEY_FILE="server.key"
CRT_FILE="server.crt"
DAYS=365
DOMAIN="localhost"

main(){
    # Parse command line arguments
    parse "$@"
    choices

    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "$KEY_FILE" \
        -out "$CRT_FILE" \
        -days "$DAYS"  \
        -subj "/CN=$DOMAIN" \
        -addext "subjectAltName=DNS:$DOMAIN,IP:127.0.0.1"

    choices
    echo "Done!"
}

parse(){
    local SHORT_OPTS="
    h
    k:
    c:
    d:
    D:
    "
    local LONG_OPTS="
    help,
    key:,
    cert:,
    days:,
    domain:,
    "
    local TEMP=$(getopt \
        -o "$SHORT_OPTS" \
        --long "$LONG_OPTS" \
        -n 'generate-cert' -- "$@")

    if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

    # Note the quotes around '$TEMP': they are essential!
    eval set -- "$TEMP"

    while true; do
        case "$1" in 
            -h | --help )    help ;;
            -k | --key )     KEY_FILE="$2"; shift 2 ;;
            -c | --cert )    CRT_FILE="$2"; shift 2 ;;
            -d | --days )    DAYS="$2"; shift 2 ;;
            -D | --domain )  DOMAIN="$2"; shift 2 ;;
            -- ) shift; break ;;
            * ) break ;;
        esac
    done
}

help(){
    echo "================="
    echo "  -h | --help            Display this help and exit"
    echo "  -k | --key <file>      Private key output file (default: server.key)"
    echo "  -c | --cert <file>     Public certificate output file (default: server.crt)"
    echo "  -d | --days <days>     Validity in days (default: 365)"
    echo "  -D | --domain <domain> Domain / CN (default: localhost)"
    exit 0
    echo "================="
}

choices(){
    echo "================="
    echo "OS:               $OSTYPE"
    echo "KEY_FILE:         $KEY_FILE"
    echo "CRT_FILE:         $CRT_FILE"
    echo "DAYS:             $DAYS"
    echo "DOMAIN:           $DOMAIN"
    echo "================="
}

main "$@"