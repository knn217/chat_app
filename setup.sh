#!/bin/bash

SCRIPTDIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

HELP=false
CLEAN=false
BUILD_PROFILE=""
LOG_LEVEL=""
RUN_PROFILE=""
PROFILING=false
PROFILING_TYPE=""
JOBS=1

main(){
    parse "$@"
    help
    choices
    setup_env_linux
    setup_env_windows
    setup_cargo
    build
    run
    choices
}

parse(){
    local SHORT_OPTS="
    h
    c
    b:
    v
    r:
    p:
    j:
    "
    local LONG_OPTS="
    help,
    clean,
    build:,
    verbose,
    run:,
    profile:,
    jobs:
    "
    local TEMP=$(getopt \
        -o "$SHORT_OPTS" \
        --long "$LONG_OPTS" \
        -n 'setup' -- "$@")

    if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

    # Note the quotes around '$TEMP': they are essential!
    eval set -- "$TEMP"
    echo "$@"

    while true; do
        case "$1" in 
            -h | --help )    HELP=true; shift ;;
            -c | --clean )   CLEAN=true; shift ;;
            -b | --build )   BUILD_PROFILE="$2"; shift 2 ;;
            -v | --verbose ) LOG_LEVEL=-vv; shift ;;
            -r | --run )     RUN_PROFILE="$2"; shift 2 ;;
            -p | --profile ) PROFILING=true; PROFILING_TYPE="$2"; shift 2 ;;
            -j | --jobs )    JOBS="$2"; shift 2 ;;
            -- ) shift; break ;;
            * ) break ;;
        esac
    done
}

help(){
    if [ "$HELP" == "false" ]; then
        return
    fi
    echo "================="
    echo "Arguments:"
    echo "<-h | --help>:                 Print help message"
    echo "<-c | --clean>:                Toggle to clean cargo build cache"
    echo "<-b | --build>:                Build one of the targets in cargo.toml         [dev | release | ...]"
    echo "<-v | --verbose>:              Toggle to enable verbosed logs"
    echo "<-r | --run>:                  Run one of the targets in cargo.toml           [dev | release | ...]"
    echo "<-p | --profile>:              Run perf profiling, use one of the categories  ["" | mem | c2c | sched | ...]"
    echo "<-j | --jobs>:                 The number of build jobs                       [1 | 2 | 3 | ...]"
    echo "================="
    exit 0
}

choices(){
    echo "================="
    echo "OS:               $OSTYPE"
    echo "CLEAN:            $CLEAN"
    echo "BUILD_PROFILE:    $BUILD_PROFILE"
    echo "LOG_LEVEL:        $LOG_LEVEL"
    echo "RUN_PROFILE:      $RUN_PROFILE"
    echo "PROFILING:        $PROFILING"
    echo "PROFILING_TYPE:   $PROFILING_TYPE"
    echo "JOBS:             $JOBS"
    echo "================="
}

setup_env_linux(){
    if [ "$OSTYPE" != "linux-gnu" ]; then
        return
    fi
    local packages=(
        # rust and cargo installation use a custom command(https://doc.rust-lang.org/book/ch01-01-installation.html)
        # Utilities
        tree
        # Slang compiler
        slang-compiler
        # cmake
        git ninja-build python3
        # For perf
        linux-tools-common linux-tools-generic linux-tools-$(uname -r)
    )
    for pkg in "${packages[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            echo "Installing $pkg..."
            sudo apt install -y "$pkg"
        else
            echo "$pkg already installed"
        fi
    done
}

setup_env_windows(){
    if [ "$OSTYPE" != "msys" ]; then
        return
    fi
    local packages=(
        # Rust
        Rustlang.Rustup
        # jq for parsing json with comands
        jqlang.jq
        #clang
        # "LLVM.LLVM --version 21.1.8"
        # Ninja-build.Ninja
    )
    for pkg in "${packages[@]}"; do
        pkg_name="${pkg%% *}"
        if ! winget list --id=$pkg_name --exact >/dev/null 2>&1; then
            echo "Installing $pkg..."
            winget install --id=$pkg --exact --silent --accept-package-agreements --accept-source-agreements
        else
            echo "$pkg already installed"
        fi
    done
}

setup_cargo(){
    # Install cargo cache
    local packages=(
        cargo-cache
    )
    for pkg in "${packages[@]}"; do
        cargo install "$pkg"
    done
}

build(){
    if [ "$CLEAN" != "false" ] && confirm "Clean build cache?"; then
        cargo cache -a
        cargo clean
    fi
    if [ -z "${BUILD_PROFILE}" ]; then
        return
    fi
    # Fix linter warnings, block until all fixed
    (cargo clippy --workspace --all-targets --fix --allow-dirty) > /dev/null 2>&1
    # Format code
    cargo fmt
    # Final check, exit if fail
    (cargo clippy --workspace --all-targets) || exit 1
    # Build
    local PACKAGES=(
        backend
        frontend
    )
    for PKG in "${PACKAGES[@]}"; do
        local JSON=$(RUST_BACKTRACE=full cargo build \
            $LOG_LEVEL \
            --jobs=$JOBS \
            --package $PKG \
            --profile=$BUILD_PROFILE \
            --message-format=json-render-diagnostics) || exit 1

        # Copy exe bin into the package folder
        # TAR_PATH=$(jq -r -s 'map(select(.reason == "compiler-artifact" and .executable != null)) | last | .filenames[0] | capture("(?<dir>.*)/[^/]+$") | .dir' <<< "$JSON") || exit 1
        # BIN_NAME=$(jq -r -s 'map(select(.reason == "compiler-artifact" and .executable != null)) | last | .executable | split("/") | last' <<< "$JSON") || exit 1
        local BIN_PATH=$(jq -r -s 'map(select(.reason == "compiler-artifact" and .executable != null)) | last | .executable' <<< "$JSON") || exit 1
        local PKG_PATH="$SCRIPTDIR/target/$BUILD_PROFILE/package/$PKG"
        # Recreate package path
        rm -rf "$PKG_PATH"
        mkdir -p "$PKG_PATH"
        cp "$BIN_PATH" "$PKG_PATH" || exit 1
    done

    # Copy resources into the frontend package folder
    resources
    # Package the database image and its installer
    database
}

database(){
    local DB_SRC="$SCRIPTDIR/database"
    local PKG_PATH="$SCRIPTDIR/target/$BUILD_PROFILE/package/database"
    local IMAGE="chat-db:local"
    # Base image tag lives in .env.example, single source of truth
    local DB_VERSION=$(grep -E '^COCKROACH_VERSION=' "$DB_SRC/.env.example" | cut -d= -f2-)

    if ! command -v docker >/dev/null 2>&1; then
        echo "docker is required to package the database" >&2
        exit 1
    fi

    # Build the image (setup scripts and SQL are baked into it)
    docker build -t "$IMAGE" --build-arg COCKROACH_VERSION="$DB_VERSION" "$DB_SRC" || exit 1

    # Recreate package path
    rm -rf "$PKG_PATH"
    mkdir -p "$PKG_PATH/scripts"

    # Export the image so it can be installed offline with `docker load`
    docker save "$IMAGE" -o "$PKG_PATH/chat-db.tar" || exit 1
    gzip -f "$PKG_PATH/chat-db.tar" || exit 1

    # Only the host-side files are needed next to the image
    cp "$DB_SRC/docker-compose.yml" "$DB_SRC/.env.example" "$DB_SRC/README.md" "$DB_SRC/install.sh" "$PKG_PATH/" || exit 1
    cp "$DB_SRC/scripts/backup.sh" "$DB_SRC/scripts/restore.sh" "$PKG_PATH/scripts/" || exit 1
    chmod +x "$PKG_PATH/install.sh" "$PKG_PATH"/scripts/*.sh
}

resources(){
    local URL_NOTOSANSMONO_REGULAR="https://raw.githubusercontent.com/notofonts/notofonts.github.io/noto-monthly-release-2026.10.01/fonts/NotoSansMono/googlefonts/variable/NotoSansMono%5Bwdth%2Cwght%5D.ttf"
    local URL_NOTOSANSMONO_CJKSC_REGULAR="https://raw.githubusercontent.com/notofonts/noto-cjk/Serif2.003/Sans/Mono/NotoSansMonoCJKsc-Regular.otf"

    local PKG_PATH="$SCRIPTDIR/target/$BUILD_PROFILE/package/frontend"
    local RES_PATH="$SCRIPTDIR/resources"
    local FONT_PATH="$RES_PATH/fonts"
    mkdir -p "$FONT_PATH"
    local NOTOSANSMONO="$FONT_PATH/NotoSansMono[wdth,wght].ttf"
    local NOTOSANSMONO_CJKSC="$FONT_PATH/NotoSansMonoCJKsc-Regular.otf"
    # Download Noto Sans Mono Variable
    curl -z "$NOTOSANSMONO" -s -L $URL_NOTOSANSMONO_REGULAR -o "$NOTOSANSMONO"
    # Download Noto Sans Mono CJK SC Regular
    curl -z "$NOTOSANSMONO_CJKSC" -s -L $URL_NOTOSANSMONO_CJKSC_REGULAR -o "$NOTOSANSMONO_CJKSC"

    # Create new paths for resouces
    mkdir -p "$PKG_PATH"
    # copy the local resources
    cp -r "$RES_PATH" "$PKG_PATH" || exit 1
}

run(){
    if [ -z "${RUN_PROFILE}" ]; then
        return
    fi

    # Run tests across all workspace crates
    cargo test --workspace || exit 1

    local TARGET_PATH="$SCRIPTDIR/target/$RUN_PROFILE"
    local PACKAGE_PATH="$TARGET_PATH/package/backend"
    local PROFILING_PATH="$TARGET_PATH/profiling"
    rm -rf "$PROFILING_PATH"
    mkdir -p "$PROFILING_PATH"
    if [ "$PROFILING" == "false" ]; then
        RUST_BACKTRACE=full "$PACKAGE_PATH/backend" || exit 1
    else
        # Save the current paranoid setting
        local OLD_PARANOID=$(cat /proc/sys/kernel/perf_event_paranoid)
        # Ensure the setting is restored when the script exits (whether it succeeds or fails)
        trap "sudo sysctl kernel.perf_event_paranoid=$OLD_PARANOID > /dev/null" EXIT
        # Temporarily lower the paranoid level for the profiling session
        sudo sysctl kernel.perf_event_paranoid=1 > /dev/null
        # Apply the kernel tracing mount permission for sched
        sudo mount -o remount,mode=755 /sys/kernel/tracing/
        # Run perf
        perf $PROFILING_TYPE record \
            -o "$PROFILING_PATH/perf.data" \
            "$PACKAGE_PATH/backend"
        perf report \
            --stdio \
            --no-inline \
            --no-children \
            --hierarchy \
            -v \
            -i "$PROFILING_PATH/perf.data" \
            > "$PROFILING_PATH/report.txt"
        echo "================="
        echo "Report written at: $PROFILING_PATH/report.txt"
    fi

}

confirm(){
    # If stdin is NOT a terminal (non-interactive/CI/cron/pipe), auto-accept
    if [ ! -t 0 ]; then
        return 0
    fi

    local prompt="${1:-Are you sure?} [y/N] "
    read -r -p "$prompt" response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0;;
        *)                 return 1;;
    esac
}

main "$@"