# chat_app

There is a `setup.sh` bash script at the root dir, this script is the main utility for all operations in this repo

## Usage
```
"Arguments:"
"<-h | --help>:                 Print help message"
"<-c | --clean>:                Toggle to clean cargo build cache"
"<-b | --build>:                Build one of the targets in cargo.toml         [dev | release | ...]"
"<-v | --verbose>:              Toggle to enable verbosed logs"
"<-r | --run>:                  Run one of the targets in cargo.toml           [dev | release | ...]"
"<-p | --profile>:              Run perf profiling, use one of the categories  ["" | mem | c2c | sched | ...]"
"<-j | --jobs>:                 The number of build jobs                       [1 | 2 | 3 | ...]"
```
